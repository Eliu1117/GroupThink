//
//  SessionViewModel.swift
//  Screen time demo
//
//  Real-time session state, countdown, and local blocking for a group study hall.
//

import Combine
import FamilyControls
import FirebaseFirestore
import Foundation
import SwiftUI
import UIKit

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var session: StudySession?
    @Published private(set) var participants: [SessionParticipant] = []
    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    /// GRO-21: Display names hydrated for every participant UID seen in this session.
    @Published private(set) var participantNames: [String: String] = [:]
    /// GRO-20: Exposed so GroupDetailView can conditionally show the start button.
    @Published private(set) var creatorOnlyStart: Bool = true
    /// Published when a session finishes; drives the animated summary sheet.
    @Published var sessionSummary: SessionSummary?
    /// GRO-11: drives the break vote bottom sheet.
    @Published var showBreakVoteSheet = false
    /// GRO-35: true while the group-approved break is in progress (running or paused).
    @Published private(set) var isOnBreak: Bool = false
    /// GRO-35: true while the break is paused by the host.
    @Published private(set) var isBreakPaused: Bool = false
    /// GRO-35: seconds remaining in the current break window.
    @Published private(set) var breakSecondsRemaining: Int = 0

    private var groupID: String?
    private var currentUID: String?
    private var sessionListener: ListenerRegistration?
    private var countdownTask: Task<Void, Never>?
    private var didApplyBlocking = false
    private var previousStatus: SessionStatus?
    private var scheduledEndDate: Date?
    private var isTearingDown = false
    /// Prevents duplicate summaries when multiple end signals fire for one session.
    private var lastSummarizedSessionID: String?

    // GRO-11: tracks vote IDs to avoid duplicate side-effects on repeated Firestore snapshots.
    private var observedBreakVoteID: String?
    private var resolvedBreakVoteID: String?
    private var breakVoteExpiryTask: Task<Void, Never>?
    private var breakCountdownTask: Task<Void, Never>?
    private static let breakDurationSec = 600   // 10-minute break

    // GRO-40: accumulates focus minutes earned across EARLIER sub-sessions of a back-to-back
    // cycle. The final sub-session's minutes are added on top via `computeEarnedMinutes` when
    // the summary is built, since that one still goes through the normal end-of-session path.
    private var cycleMinutesEarnedSoFar: Int = 0

    // MARK: - Group settings
    private var strictMode: Bool = false
    private var requireBlocklist: Bool = true
    private var allowLateJoin: Bool = true
    private var groupName: String = "your group"
    // GRO-11: copied into the session document at creation time
    private var breakVotingEnabled: Bool = false
    private var breakWindowSeconds: Int = 120
    private var breakCooldownPercent: Int = 20
    // GRO-11: every-other-session penalty flag read from the Group document.
    private var breakPassedLastSession: Bool = false

    deinit {
        sessionListener?.remove()
        countdownTask?.cancel()
        breakVoteExpiryTask?.cancel()
    }

    // MARK: - Configuration

    func configure(groupID: String, currentUID: String?) {
        guard self.groupID != groupID || self.currentUID != currentUID else { return }

        stopListening()
        self.groupID = groupID
        self.currentUID = currentUID
        session = nil
        participants = []
        participantNames = [:]
        errorMessage = nil
        secondsRemaining = 0
        didApplyBlocking = false
        previousStatus = nil
        scheduledEndDate = nil
        showBreakVoteSheet = false
        breakVoteExpiryTask?.cancel()
        breakVoteExpiryTask = nil
        breakCountdownTask?.cancel()
        breakCountdownTask = nil
        observedBreakVoteID = nil
        resolvedBreakVoteID = nil
        isOnBreak = false
        isBreakPaused = false
        breakSecondsRemaining = 0
        cycleMinutesEarnedSoFar = 0
        isAdvancingCycle = false

        guard currentUID != nil else { return }

        print("[Firestore Session] Starting listener for group \(groupID)")
        sessionListener = SessionService.shared.observeLiveSession(groupID: groupID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success(let session):
                    self.handleSessionUpdate(session)

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    print("[Firestore Session] Listener error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Applies group settings from the live Group model.
    func updateGroupSettings(group: Group) {
        strictMode = group.strictMode
        requireBlocklist = group.requireBlocklist
        allowLateJoin = group.allowLateJoin
        creatorOnlyStart = group.creatorOnlyStart
        groupName = group.name
        // GRO-11: break voting settings (snapshotted into the session at creation)
        breakVotingEnabled = group.breakVotingEnabled
        breakWindowSeconds = group.breakWindowSeconds
        breakCooldownPercent = group.breakCooldownPercent
        // GRO-11: read flag — only acted upon in createSession, never mid-session.
        breakPassedLastSession = group.breakPassedLastSession
    }

    /// GRO-21: Seeds display names from the pre-fetched member roster.
    /// Only fills gaps; does not overwrite names already resolved from Firestore.
    func seedParticipantNames(_ names: [String: String]) {
        for (uid, name) in names {
            if participantNames[uid] == nil {
                participantNames[uid] = name
            }
        }
    }

    func stopListening() {
        detachSessionListener()
        haltLocalSessionInfrastructure(reason: "listener stop")
    }

    // MARK: - Actions

    /// Option B: blocks starting/joining a non-strict session without a configured
    /// blocklist (strict mode shields everything, so no blocklist is needed).
    private func satisfiesBlocklistPolicy(strictSession: Bool) -> Bool {
        guard requireBlocklist, !strictSession else { return true }
        return BlocklistStore.shared.hasSelection
    }

    /// GRO-40: `totalSessionsInCycle` > 1 configures a back-to-back (Pomodoro-style) cycle —
    /// automatic breaks are inserted between sub-sessions until the last one finishes.
    func createSession(durationMin: Int = 25, totalSessionsInCycle: Int = 1) async -> Bool {
        guard let groupID, let currentUID else {
            errorMessage = SessionServiceError.notSignedIn.localizedDescription
            return false
        }

        guard satisfiesBlocklistPolicy(strictSession: strictMode) else {
            errorMessage = "This group requires a blocklist. Choose apps to block on the Home tab first."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            // Cooldown in minutes: breakCooldownPercent % of session duration, min 1 min.
            let cooldownMinutes = max(1, Int(ceil(Double(durationMin) * Double(breakCooldownPercent) / 100.0)))
            // GRO-11: if the previous session ended via a passed break vote, start this one locked.
            let initialPenaltyLock = breakPassedLastSession
            _ = try await SessionService.shared.createSession(
                groupID: groupID,
                hostUID: currentUID,
                durationMin: durationMin,
                strictMode: strictMode,
                breakVotingEnabled: breakVotingEnabled,
                breakWindowSeconds: breakWindowSeconds,
                breakCooldownMinutes: cooldownMinutes,
                penaltyLock: initialPenaltyLock,
                totalSessionsInCycle: totalSessionsInCycle
            )
            let capturedGroupID = groupID
            // GRO-33: persist last-used duration so all members' pickers stay in sync.
            Task { try? await GroupService.shared.updateLastSessionDuration(groupID: capturedGroupID, durationMin: durationMin) }
            // GRO-11: consume the cross-session penalty flag now that the new session has it.
            if initialPenaltyLock {
                Task { try? await GroupService.shared.clearBreakPenalty(groupID: capturedGroupID) }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error creating session: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Break voting (GRO-11)

    /// Initiates a break vote. All gate conditions are checked on `session.canInitiateBreakVote`.
    func initiateBreakVote() async {
        guard let groupID, let currentUID, let session, session.canInitiateBreakVote else { return }
        do {
            try await BreakVoteService.shared.initiateVote(
                groupID: groupID,
                initiatorUID: currentUID,
                windowSeconds: session.breakWindowSeconds
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[BreakVote] Error initiating: \(error.localizedDescription)")
        }
    }

    /// Casts the current user's vote on the in-flight break vote.
    func castBreakVote(inFavor: Bool) async {
        guard let groupID, let currentUID, let session else { return }
        let total = session.participants.count
        do {
            try await BreakVoteService.shared.castVote(
                groupID: groupID,
                voterUID: currentUID,
                inFavor: inFavor,
                totalParticipants: total
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[BreakVote] Error casting vote: \(error.localizedDescription)")
        }
    }

    func joinLobby() async -> Bool {
        guard let groupID, let currentUID, let session else { return false }
        guard session.status == .lobby || (session.status == .active && allowLateJoin) else { return false }

        guard satisfiesBlocklistPolicy(strictSession: session.strictMode) else {
            errorMessage = "This group requires a blocklist. Choose apps to block on the Home tab first."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await SessionService.shared.joinSession(
                groupID: groupID,
                userUID: currentUID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error joining session: \(error.localizedDescription)")
            return false
        }
    }

    func launchSession() async -> Bool {
        guard let groupID, let currentUID, let session else { return false }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await SessionService.shared.launchSession(
                groupID: groupID,
                hostUID: currentUID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error launching session: \(error.localizedDescription)")
            return false
        }
    }

    func updateMyState(_ state: ParticipantState) async {
        await updatePresence(state)
    }

    /// Writes the local user's presence to `participants.{uid}.state` on the active session.
    func updatePresence(_ state: ParticipantState) async {
        guard let groupID, let currentUID, let session, session.status == .active else { return }
        guard session.participants[currentUID] != nil else { return }

        do {
            try await SessionService.shared.updatePresence(
                groupID: groupID,
                userUID: currentUID,
                state: state
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Presence] Error updating user state: \(error.localizedDescription)")
        }
    }

    /// Responds to app lifecycle changes during an active session.
    ///
    /// Note: flushing pending "opened" events on `.active` is intentionally NOT gated behind
    /// `session?.status == .active`. A user can open several blocked apps in strict mode and
    /// not return to this screen until well after the session has ended (or this group's
    /// listener has already cleared `session`) — if the flush only ran while a session looked
    /// active, those queued attempts would never make it to Firestore and the group would
    /// never see that the apps were opened.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            guard let session, session.status == .active, isInLobby else { return }
            print("[Firestore Presence] App entered background — marking left")
            Task { await updatePresence(.left) }

        case .active:
            Task {
                await ExtensionAuthTokenBridge.persistIDTokenForExtension(forcingRefresh: false)
                // Flush pending opened events regardless of isInLobby: the Firestore snapshot
                // may be transiently stale when the scene becomes active, so we must not
                // skip a pending opened event just because isInLobby is briefly false.
                let flushedOpened = await flushPendingOpenedEvents()
                if !flushedOpened, let session, session.status == .active, isInLobby, myState == .left {
                    print("[Firestore Presence] App became active — restoring focused")
                    await updatePresence(.focused)
                }
            }

        case .inactive:
            break

        @unknown default:
            break
        }
    }

    /// Flushes extension-queued `opened` events from the App Group into Firestore.
    /// Delegates to the app-wide flusher (see `PendingOpenedEventFlusher`) so behavior is
    /// identical whether triggered from this screen or from the global scene-phase observer.
    @discardableResult
    func flushPendingOpenedEvents() async -> Bool {
        await PendingOpenedEventFlusher.flush()
    }

    /// GRO-40: `cycleEndedEarly` should only be true when a back-to-back cycle is cut short
    /// with sessions/breaks still remaining — see `endCycleEarly()` for the host-facing entry
    /// point that computes this automatically.
    @discardableResult
    func endSession(cycleEndedEarly: Bool = false) async -> Bool {
        guard let groupID, let currentUID, let activeSession = session, !isTearingDown else { return false }

        let sessionID = activeSession.id
        isTearingDown = true
        isSubmitting = true
        errorMessage = nil

        // Halt monitoring and extension context before the Firestore write to prevent races.
        haltLocalSessionInfrastructure(reason: "end session")

        defer {
            isSubmitting = false
            isTearingDown = false
        }

        do {
            try await SessionService.shared.endSession(
                groupID: groupID,
                requesterUID: currentUID,
                cycleEndedEarly: cycleEndedEarly
            )
            handleSessionEnd(for: activeSession)
            // GRO-17: Listener is kept alive here so it can pick up the NEXT session
            // immediately after the host creates one. The listener will emit nil once
            // Firestore reflects the "ended" status and finalizeSessionTeardown cleans up.
            self.session = nil
            participants = []
            previousStatus = nil
            print("[Session] Session \(sessionID) ended — listener retained for next session")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error ending session: \(error.localizedDescription)")
            reattachListenerIfNeeded()
            return false
        }
    }

    /// GRO-40: host-only action that ends the ENTIRE back-to-back cycle immediately, from any
    /// point — mid focus session or mid inter-session break — bypassing any remaining
    /// sub-sessions/breaks and routing every participant straight to the summary via the same
    /// Firestore `status: ended` signal used for a natural finish.
    @discardableResult
    func endCycleEarly() async -> Bool {
        guard isHost, let session else { return false }
        return await endSession(cycleEndedEarly: session.hasMoreSessionsInCycle)
    }

    // MARK: - Computed

    /// Expose the authenticated UID so views can display per-user state (e.g. break vote).
    var uid: String? { currentUID }

    var isHost: Bool {
        guard let session, let currentUID else { return false }
        return session.hostUid == currentUID
    }

    var isInLobby: Bool {
        guard let session, let currentUID else { return false }
        return session.participants[currentUID] != nil
    }

    /// GRO-14: True when an active session exists and the user hasn't joined yet.
    var canLateJoin: Bool {
        guard let session, session.status == .active else { return false }
        return !isInLobby && allowLateJoin
    }

    var myState: ParticipantState? {
        guard let session, let currentUID else { return nil }
        return session.participants[currentUID]
    }

    var formattedCountdown: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Private

    private func handleSessionUpdate(_ session: StudySession?) {
        guard !isTearingDown else { return }

        if let session {
            let statusChanged = previousStatus != session.status
            previousStatus = session.status
            self.session = session
            participants = session.participantList
            hydrateParticipantNames(for: session) // GRO-21

            switch session.status {
            case .lobby:
                stopCountdown()
                SessionContextStore.shared.setActiveSession(nil)
                SessionActivityScheduler.stopMonitoring()
                scheduledEndDate = nil
                // GRO-40: a lobby always represents the FIRST sub-session of a fresh cycle
                // (advancing between sub-sessions goes straight from break to `.active`,
                // never back through `.lobby`), so this is the right place to zero the
                // cross-session accumulator for the new cycle.
                cycleMinutesEarnedSoFar = 0
                if didApplyBlocking {
                    BlockingManager.shared.clear()
                    didApplyBlocking = false
                }

            case .active:
                // GRO-40: never touch the focus countdown/shields/monitoring while a break is
                // genuinely in progress — `syncBreakState` owns everything break-related below.
                // (Defense in depth alongside the `.estimate` timestamp fix in `StudySession`:
                // even a brief false read of `breakIsActive` here previously caused shields to
                // be re-applied against a stale, already-past `endDate`, which could spiral
                // into a rapid start-break/advance-session loop on very short test durations.)
                if !session.breakIsActive {
                    // Set a display value immediately so the UI never shows the default
                    // 0:00 state while prepareActiveSession awaits the async token refresh.
                    // Only set if currently zero — avoids resetting mid-session on presence updates.
                    if secondsRemaining == 0 {
                        if let endDate = session.endDate {
                            updateRemainingSeconds(until: endDate)
                        } else {
                            secondsRemaining = session.durationMin * 60
                        }
                    }
                    Task {
                        await prepareActiveSession(session, statusChanged: statusChanged)
                    }
                }
                // GRO-11: react to break vote state changes on every snapshot.
                handleBreakVoteUpdate(session)
                // GRO-35: sync break countdown from Firestore timestamps (navigation-safe).
                syncBreakState(from: session)

            case .ended:
                handleSessionEnd(for: session)
                finalizeSessionTeardown(clearSessionDocument: true)
            }
        } else {
            if previousStatus == .active, let lastSession = self.session {
                handleSessionEnd(for: lastSession)
            }
            finalizeSessionTeardown(clearSessionDocument: true)
        }
    }

    // MARK: - Session end (stats + summary + notification)

    /// Single funnel for every end-of-session signal: awards stats, publishes the
    /// animated summary, and posts a local notification when the app isn't foregrounded.
    private func handleSessionEnd(for session: StudySession) {
        awardStats(for: session)
        presentSummary(for: session)
    }

    private func computeEarnedMinutes(for session: StudySession) -> Int {
        guard let currentUID,
              session.participants[currentUID] == .focused,
              let startAt = session.startAt
        else { return 0 }

        let elapsed = Int((Date().timeIntervalSince(startAt) / 60).rounded())
        return min(session.durationMin, max(elapsed, 0))
    }

    private func presentSummary(for session: StudySession) {
        guard let currentUID,
              session.participants[currentUID] != nil, // observers get no summary
              session.startAt != nil,                  // session never went active
              lastSummarizedSessionID != session.id
        else { return }

        lastSummarizedSessionID = session.id

        let summary = SessionSummary(
            id: session.id,
            groupName: groupName,
            durationMin: session.durationMin,
            startAt: session.startAt,
            endedAt: Date(),
            participants: session.participantList,
            memberNames: participantNames,
            myUID: currentUID,
            myState: session.participants[currentUID],
            // GRO-40: cumulative across every sub-session in the cycle, not just this one.
            minutesEarned: cycleMinutesEarnedSoFar + computeEarnedMinutes(for: session),
            wasStrictMode: session.strictMode,
            totalSessionsInCycle: session.totalSessionsInCycle,
            completedSessionIndex: session.currentSessionIndex,
            cycleEndedEarly: session.cycleEndedEarly
        )

        withAnimation(.spring(duration: 0.5)) {
            sessionSummary = summary
        }

        // Banner only when the user won't see the in-app summary transition.
        if UIApplication.shared.applicationState != .active {
            PushNotificationService.shared.postSessionEndedNotification(
                groupName: groupName,
                minutesEarned: summary.minutesEarned
            )
        }
    }

    /// Applies shields for the active session.
    /// Strict mode: blocks ALL apps except the user's local whitelist (no tokens cross devices).
    /// Normal mode: blocks the user's personal blocklist, with the whitelist taking precedence.
    private func applyLocalBlocking(for session: StudySession) {
        let whitelist = BlocklistStore.shared.whitelistSelection

        if session.strictMode {
            BlockingManager.shared.blockStrict(whitelist: whitelist)
            didApplyBlocking = true
            print("[Session] Applied STRICT shields (whitelist: \(BlocklistStore.shared.whitelistCount) app(s))")
        } else {
            // Explicitly subtract whitelist tokens from the blocklist so that an app
            // present in both collections is treated as allowed. Whitelist always wins.
            let effective = effectiveBlockSelection(whitelist: whitelist)
            guard !effective.applicationTokens.isEmpty || !effective.categoryTokens.isEmpty else {
                print("[Session] Blocklist is empty or fully covered by whitelist — skipping shield")
                return
            }
            BlockingManager.shared.block(selection: effective)
            didApplyBlocking = true
            print("[Session] Applied personal shields")
        }

        if let endDate = session.endDate {
            scheduleBackgroundMonitoring(until: endDate, selection: effectiveMonitorSelection(for: session))
        }
    }

    /// Returns the personal blocklist with whitelist tokens subtracted.
    /// Used for both shield application and DeviceActivity event registration.
    private func effectiveBlockSelection(whitelist: FamilyActivitySelection) -> FamilyActivitySelection {
        var effective = BlocklistStore.shared.selection
        effective.applicationTokens.subtract(whitelist.applicationTokens)
        effective.categoryTokens.subtract(whitelist.categoryTokens)
        return effective
    }

    /// Returns the selection to use when registering the openedBlockedApp DeviceActivity event.
    /// Both strict and normal mode use blocklist-minus-whitelist.
    ///
    /// Previously, strict mode returned an empty selection under the assumption that the shield
    /// extension would handle detection, but that over-corrected and stopped all attempt tracking.
    /// `effectiveBlockSelection` already subtracts whitelisted tokens, so it is safe for both modes:
    /// a whitelisted app that also appears on the blocklist will NOT trigger the event.
    private func effectiveMonitorSelection(for session: StudySession) -> FamilyActivitySelection {
        effectiveBlockSelection(whitelist: BlocklistStore.shared.whitelistSelection)
    }

    /// GRO-21: Detects participant UIDs not yet in `participantNames` and fetches
    /// their display names from Firestore in the background.
    private func hydrateParticipantNames(for session: StudySession) {
        let knownUIDs = Set(participantNames.keys)
        let newUIDs = Set(session.participants.keys).subtracting(knownUIDs)
        guard !newUIDs.isEmpty else { return }

        Task {
            let fetched = await UserService.shared.fetchDisplayNames(for: Array(newUIDs))
            await MainActor.run {
                for (uid, name) in fetched where self.participantNames[uid] == nil {
                    self.participantNames[uid] = name
                }
            }
        }
    }

    /// Caches auth token and App Group context before DeviceActivity monitoring begins.
    private func prepareActiveSession(_ session: StudySession, statusChanged: Bool) async {
        // Start the countdown immediately — before any async work — so the loop begins
        // ticking from the very first second without being blocked by the token refresh.
        startCountdown(for: session)

        persistActiveSessionContext(for: session)

        if statusChanged || !didApplyBlocking {
            applyLocalBlocking(for: session)
        }
        if let endDate = session.endDate, scheduledEndDate != endDate {
            scheduleBackgroundMonitoring(until: endDate, selection: effectiveMonitorSelection(for: session))
            scheduledEndDate = endDate
        } else if statusChanged, session.endDate == nil {
            scheduleBackgroundMonitoring(
                until: Date().addingTimeInterval(TimeInterval(session.durationMin * 60)),
                selection: effectiveMonitorSelection(for: session)
            )
        }

        // Token refresh is async; must complete before extensions make authenticated writes,
        // but the countdown and shields do not depend on it.
        if statusChanged {
            await ExtensionAuthTokenBridge.persistIDTokenForExtension(forcingRefresh: true)
        }
        await flushPendingOpenedEvents()
    }

    // MARK: - Break vote lifecycle (GRO-11)

    private func handleBreakVoteUpdate(_ session: StudySession) {
        if let vote = session.activeBreakVote, vote.isPending {
            guard observedBreakVoteID != vote.id else { return }
            observedBreakVoteID = vote.id
            showBreakVoteSheet = true

            // Post local notification unless the user opted out.
            let notifEnabled = UserDefaults.standard.object(forKey: StudyHallConstants.breakVoteNotificationsEnabledKey) as? Bool ?? true
            if notifEnabled {
                let name = participantNames[vote.initiatorUid] ?? "A member"
                PushNotificationService.shared.postBreakVoteStartedNotification(
                    groupName: groupName,
                    initiatorName: name
                )
            }

            scheduleBreakVoteExpiry(voteID: vote.id, deadline: vote.deadline)

        } else if let vote = session.activeBreakVote, !vote.isPending {
            // Vote just resolved — cancel the expiry task (no longer needed).
            breakVoteExpiryTask?.cancel()
            breakVoteExpiryTask = nil

            // Guard: only process resolution side-effects once per vote ID.
            if resolvedBreakVoteID != vote.id {
                resolvedBreakVoteID = vote.id

                if vote.status == .passed {
                    // GRO-39: a passed vote ends the CURRENT sub-session immediately — no break
                    // timer is started for IT. It does NOT cancel the rest of a back-to-back
                    // cycle: if more sub-sessions remain, this just mirrors a normal early
                    // finish of this sub-session (credit its progress, then move into the
                    // regular inter-session break); only when this is the LAST sub-session does
                    // it actually end the whole session/cycle. Lift shields/monitoring on every
                    // device right away so there's no gap waiting for Firestore to round-trip.
                    if didApplyBlocking {
                        BlockingManager.shared.clear()
                        didApplyBlocking = false
                        print("[BreakVote] Shields lifted — vote passed")
                    }
                    SessionActivityScheduler.stopMonitoring()
                    stopCountdown()

                    if session.hasMoreSessionsInCycle {
                        accumulateCycleProgress(for: session)
                        if isHost {
                            Task { await self.advanceCycleToBreak(for: session) }
                        }
                    } else if isHost {
                        Task { _ = await self.endSession() }
                    }

                    // GRO-11: flag the group so the NEXT session starts penalty-locked.
                    if let gid = groupID {
                        Task { try? await GroupService.shared.markBreakPassed(groupID: gid) }
                    }
                }
            }

            // Dismiss the sheet after 2 s so users can read the result banner.
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showBreakVoteSheet = false
            }

        } else {
            // No vote in flight.
            showBreakVoteSheet = false
        }
    }

    // MARK: - Break state (GRO-35)

    /// Computed break time formatted as "M:SS" for display in SessionView.
    var formattedBreakCountdown: String {
        let m = breakSecondsRemaining / 60
        let s = breakSecondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Actions exposed to the view (host only).
    func pauseBreak() async {
        guard isHost, let groupID, let currentUID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await SessionService.shared.pauseBreak(
                groupID: groupID,
                hostUID: currentUID,
                secondsRemaining: breakSecondsRemaining
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeBreak() async {
        guard isHost, let groupID, let currentUID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await SessionService.shared.resumeBreak(
                groupID: groupID,
                hostUID: currentUID,
                secondsRemaining: breakSecondsRemaining
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Back-to-back cycle advancement (GRO-40)

    /// Guards `advanceCycleToBreak`/`advanceCycleAfterBreak` against firing twice for the
    /// same transition — the local countdown tick and a Firestore snapshot re-check can both
    /// observe "time's up" within the same moment and would otherwise race to write two
    /// competing cycle-advance documents.
    private var isAdvancingCycle = false

    /// Host-only: called when a sub-session's focus timer hits zero and more sub-sessions
    /// remain in the cycle. Stops this sub-session's local infrastructure and writes the
    /// Pomodoro-computed break to Firestore; every client (including this one) picks the
    /// break up via `syncBreakState` on the next snapshot.
    private func advanceCycleToBreak(for session: StudySession) async {
        guard isHost, let groupID, !isAdvancingCycle else { return }
        isAdvancingCycle = true
        defer { isAdvancingCycle = false }

        let breakSeconds = PomodoroBreakCalculator.breakSeconds(
            afterSessionIndex: session.currentSessionIndex,
            sessionDurationMin: session.durationMin
        )

        do {
            try await SessionService.shared.startBreak(
                groupID: groupID,
                hostUID: currentUID ?? "",
                durationSec: breakSeconds
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[Cycle] Failed to start inter-session break: \(error.localizedDescription)")
        }
    }

    /// Host-only: called when the inter-session break's countdown reaches zero (or the host
    /// skips it early via `endBreakEarly()`). Overwrites the session slot with the next
    /// sub-session; every client (including this one) picks it up as a fresh `.active`
    /// snapshot.
    private func advanceCycleAfterBreak(for session: StudySession) async {
        guard isHost, let groupID, let currentUID, !isAdvancingCycle else { return }
        isAdvancingCycle = true
        defer { isAdvancingCycle = false }

        do {
            try await SessionService.shared.advanceToNextSessionInCycle(
                groupID: groupID,
                hostUID: currentUID
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[Cycle] Failed to advance to next sub-session: \(error.localizedDescription)")
        }
    }

    /// GRO-40: host-only — skips whatever remains of the current inter-session break and
    /// moves straight into the next sub-session, as if its countdown had already hit zero.
    /// Distinct from `endCycleEarly()`, which cancels the ENTIRE remaining cycle instead of
    /// just the break.
    @discardableResult
    func endBreakEarly() async -> Bool {
        guard isHost, let session, session.breakIsActive else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        await advanceCycleAfterBreak(for: session)
        return true
    }

    /// Every device (host and participants alike) credits its own stats/minutes for a
    /// sub-session that just finished mid-cycle — mirrors `awardStats`, which normally only
    /// fires once, at the very end of a (single) session.
    private func accumulateCycleProgress(for session: StudySession) {
        cycleMinutesEarnedSoFar += computeEarnedMinutes(for: session)
        awardStats(for: session)
    }

    /// Syncs the local break state with the Firestore session snapshot.
    /// Called on every `.active` snapshot so navigation away/back or app restart
    /// never resets the countdown (GRO-35).
    private func syncBreakState(from session: StudySession) {
        guard session.breakIsActive else {
            if isOnBreak { stopBreakCountdown() }
            return
        }

        // GRO-40: transitioning into a break — halt local shields/monitoring/countdown for
        // EVERY device (not just the host) the moment Firestore reflects the break start.
        // Breaks are now driven exclusively by the back-to-back cycle timer (GRO-39 removed
        // the break-vote → break-timer path), but this stays generic so any future
        // `breakStartedAt` writer gets the same behavior for free.
        if !isOnBreak {
            if didApplyBlocking {
                BlockingManager.shared.clear()
                didApplyBlocking = false
            }
            SessionActivityScheduler.stopMonitoring()
            stopCountdown()
        }

        isOnBreak = true
        isBreakPaused = session.breakIsPaused

        let firestoreRemaining = session.computedBreakSecondsRemaining

        if session.breakIsPaused {
            // Paused: freeze the display value and stop the local tick.
            breakSecondsRemaining = firestoreRemaining
            stopLocalBreakTick()
        } else {
            // Running: seed the value if not already ticking, or correct significant drift.
            if breakCountdownTask == nil {
                breakSecondsRemaining = firestoreRemaining
                startLocalBreakTick()
            } else {
                let drift = abs(breakSecondsRemaining - firestoreRemaining)
                if drift > 3 { breakSecondsRemaining = firestoreRemaining }
            }

            // Host-side expiry check: advance to the next sub-session (other clients wait
            // for the host's Firestore write, same as before).
            if firestoreRemaining == 0 && isHost {
                Task { await self.advanceCycleAfterBreak(for: session) }
            }
        }
    }

    /// Starts a local 1-second tick task for smooth UI rendering.
    /// The true countdown value is re-anchored from Firestore on each snapshot.
    ///
    /// GRO-40 fix: `syncBreakState`'s expiry check only re-runs when a NEW Firestore snapshot
    /// arrives, but nothing writes to the session doc while a break is quietly counting down —
    /// so without an active driver here, the break could sit at 0s indefinitely until some
    /// unrelated write (e.g. a pause/resume tap) happened to trigger a snapshot and give the
    /// expiry check another chance to run. The host's local tick is now the primary driver:
    /// once it reaches zero, it advances the cycle itself instead of waiting on Firestore.
    private func startLocalBreakTick() {
        breakCountdownTask?.cancel()
        breakCountdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                var shouldAdvance = false
                var sessionSnapshot: StudySession?
                await MainActor.run {
                    if self.breakSecondsRemaining > 0 {
                        self.breakSecondsRemaining -= 1
                    }
                    if self.breakSecondsRemaining <= 0, self.isHost, let session = self.session {
                        shouldAdvance = true
                        sessionSnapshot = session
                        self.breakCountdownTask?.cancel()
                        self.breakCountdownTask = nil
                    }
                }
                if shouldAdvance, let session = sessionSnapshot {
                    await self.advanceCycleAfterBreak(for: session)
                    return
                }
            }
        }
    }

    private func stopLocalBreakTick() {
        breakCountdownTask?.cancel()
        breakCountdownTask = nil
    }

    private func stopBreakCountdown() {
        stopLocalBreakTick()
        isOnBreak = false
        isBreakPaused = false
        breakSecondsRemaining = 0
    }

    /// Schedules a task that calls `expireVote` when the voting window closes.
    private func scheduleBreakVoteExpiry(voteID: String, deadline: Date) {
        breakVoteExpiryTask?.cancel()
        let delay = max(0, deadline.timeIntervalSinceNow)
        let capturedGroupID = groupID ?? ""

        breakVoteExpiryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            print("[BreakVote] Window expired for vote \(voteID)")
            try? await BreakVoteService.shared.expireVote(groupID: capturedGroupID, voteID: voteID)
        }
    }

    private func persistActiveSessionContext(for session: StudySession) {
        guard let groupID, let currentUID, session.participants[currentUID] != nil else { return }

        SessionContextStore.shared.setActiveSession(
            ActiveSessionContext(
                groupID: groupID,
                sessionID: session.id,
                userUID: currentUID
            )
        )
        // Persist the strict-mode flag so StudyHallMonitor can apply the correct
        // shield policy when intervalDidStart fires in the background.
        SessionContextStore.shared.setStrictMode(strictMode)
    }

    private func scheduleBackgroundMonitoring(
        until endDate: Date,
        selection: FamilyActivitySelection
    ) {
        do {
            try SessionActivityScheduler.startMonitoring(until: endDate, selection: selection)
        } catch {
            print("[DeviceActivity] Failed to start monitoring: \(error.localizedDescription)")
        }
    }

    private func startCountdown(for session: StudySession) {
        guard let endDate = session.endDate else {
            // startAt not yet available (server timestamp still propagating).
            // Show the full duration as a placeholder; the next Firestore snapshot
            // with startAt set will call startCountdown again to launch the real loop.
            secondsRemaining = session.durationMin * 60
            return
        }

        // Don't restart the loop if it's already running.
        // The initial display value is set by handleSessionUpdate before this is called,
        // so we don't call updateRemainingSeconds here. Calling it here while another
        // concurrent prepareActiveSession task is in flight (e.g. Task A with a local
        // server-timestamp estimate vs Task B with the confirmed server timestamp) would
        // race and cause the displayed value to jump upward before settling.
        if let existing = countdownTask, !existing.isCancelled {
            return
        }

        // Capture endDate once so the loop's reference point never shifts when Firestore
        // delivers the server-confirmed timestamp (which may differ by a few ms from the
        // local estimate), preventing mid-session jumps in the displayed value.
        let capturedEndDate = endDate

        countdownTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }

                await MainActor.run {
                    guard let session = self.session, session.status == .active else { return }

                    self.updateRemainingSeconds(until: capturedEndDate)

                    if self.secondsRemaining <= 0 {
                        self.countdownTask?.cancel()
                        Task {
                            guard let session = self.session else { return }

                            // GRO-40: more sub-sessions remain in this back-to-back cycle —
                            // insert an automatic break instead of ending the group session.
                            // Every device credits its OWN stats/minutes for the sub-session
                            // that just finished (mirrors `awardStats`, which normally only
                            // runs once at the very end); only the host advances Firestore.
                            if session.hasMoreSessionsInCycle {
                                self.accumulateCycleProgress(for: session)
                                if self.isHost {
                                    await self.advanceCycleToBreak(for: session)
                                } else {
                                    // Optimistically clear shields/monitoring now rather than
                                    // waiting for the host's `breakStartedAt` write to round-trip
                                    // back through Firestore; `syncBreakState` re-confirms (and is
                                    // idempotent) once that snapshot arrives.
                                    if self.didApplyBlocking {
                                        BlockingManager.shared.clear()
                                        self.didApplyBlocking = false
                                    }
                                    SessionActivityScheduler.stopMonitoring()
                                }
                                return
                            }

                            if self.isHost {
                                _ = await self.endSession()
                            } else {
                                self.handleSessionEnd(for: session)
                                self.haltLocalSessionInfrastructure(reason: "timer expired (participant)")
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateRemainingSeconds(until endDate: Date) {
        secondsRemaining = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// Stops countdown, DeviceActivity monitoring, App Group context, and local shields together.
    private func haltLocalSessionInfrastructure(reason: String) {
        stopCountdown()
        stopBreakCountdown()
        secondsRemaining = 0
        scheduledEndDate = nil
        SessionContextStore.shared.clearAll()
        SessionActivityScheduler.stopMonitoring()

        if didApplyBlocking {
            BlockingManager.shared.clear()
            didApplyBlocking = false
            print("[Session] Cleared local blocking — \(reason)")
        }
    }

    private func detachSessionListener() {
        sessionListener?.remove()
        sessionListener = nil
        countdownTask?.cancel()
        countdownTask = nil
        stopLocalBreakTick()
    }

    private func finalizeSessionTeardown(clearSessionDocument: Bool) {
        haltLocalSessionInfrastructure(reason: "session teardown")
        participants = []

        if clearSessionDocument {
            session = nil
            previousStatus = nil
        }
    }

    private func reattachListenerIfNeeded() {
        guard let groupID, sessionListener == nil else { return }

        print("[Session] Re-attaching listener after failed end")
        sessionListener = SessionService.shared.observeLiveSession(groupID: groupID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success(let session):
                    self.handleSessionUpdate(session)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    print("[Firestore Session] Listener error: \(error.localizedDescription)")
                }
            }
        }

        if let session, session.status == .active {
            persistActiveSessionContext(for: session)
            if let endDate = session.endDate ?? scheduledEndDate {
                scheduleBackgroundMonitoring(until: endDate, selection: BlocklistStore.shared.selection)
            }
            if !didApplyBlocking, BlocklistStore.shared.hasSelection {
                applyLocalBlocking(for: session)
            }
            startCountdown(for: session)
        }
    }

    // MARK: - Phase 5 stats

    /// Phase 5 — awards focus minutes and streaks for the LOCAL user if they stayed focused.
    /// Idempotent per session (guarded inside StatsService).
    private func awardStats(for session: StudySession) {
        guard let groupID, let currentUID else { return }
        guard session.participants[currentUID] == .focused else {
            print("[Stats] No award — local user did not stay focused")
            return
        }
        guard let startAt = session.startAt else { return }

        let elapsedMinutes = Int((Date().timeIntervalSince(startAt) / 60).rounded())
        let minutes = min(session.durationMin, max(elapsedMinutes, 0))
        guard minutes > 0 else { return }

        let sessionID = session.id
        Task {
            await StatsService.shared.recordSessionCompletion(
                groupID: groupID,
                sessionID: sessionID,
                userUID: currentUID,
                focusMinutes: minutes
            )
        }
    }
}
