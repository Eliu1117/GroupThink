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

    // MARK: - Group settings
    private var strictMode: Bool = false
    private var requireBlocklist: Bool = true
    private var allowLateJoin: Bool = true
    private var groupName: String = "your group"

    deinit {
        sessionListener?.remove()
        countdownTask?.cancel()
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

    func createSession(durationMin: Int = 25) async -> Bool {
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
            _ = try await SessionService.shared.createSession(
                groupID: groupID,
                hostUID: currentUID,
                durationMin: durationMin,
                strictMode: strictMode
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error creating session: \(error.localizedDescription)")
            return false
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
    func handleScenePhase(_ phase: ScenePhase) {
        guard let session, session.status == .active, isInLobby else { return }

        switch phase {
        case .background:
            print("[Firestore Presence] App entered background — marking left")
            Task { await updatePresence(.left) }

        case .active:
            Task {
                await ExtensionAuthTokenBridge.persistIDTokenForExtension(forcingRefresh: false)
                let flushedOpened = await flushPendingOpenedEvents()
                if !flushedOpened, myState == .left {
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
    @discardableResult
    func flushPendingOpenedEvents() async -> Bool {
        let events = SessionContextStore.shared.drainPendingOpenedEvents()
        guard !events.isEmpty else { return false }

        for event in events {
            do {
                try await SessionService.shared.markOpened(
                    groupID: event.groupID,
                    userUID: event.userUID
                )
                print("[Firestore Presence] Flushed opened event for \(event.userUID)")
            } catch {
                SessionContextStore.shared.enqueuePendingOpened(
                    for: ActiveSessionContext(
                        groupID: event.groupID,
                        sessionID: event.sessionID,
                        userUID: event.userUID
                    )
                )
                print("[Firestore Presence] Failed to flush opened event — re-queued: \(error.localizedDescription)")
            }
        }

        return true
    }

    func endSession() async -> Bool {
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
                requesterUID: currentUID
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

    // MARK: - Computed

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
                if didApplyBlocking {
                    BlockingManager.shared.clear()
                    didApplyBlocking = false
                }

            case .active:
                Task {
                    await prepareActiveSession(session, statusChanged: statusChanged)
                }

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
            minutesEarned: computeEarnedMinutes(for: session),
            wasStrictMode: session.strictMode
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
    /// Normal mode: blocks the user's personal blocklist selection.
    private func applyLocalBlocking(for session: StudySession) {
        if session.strictMode {
            BlockingManager.shared.blockStrict(whitelist: BlocklistStore.shared.whitelistSelection)
            didApplyBlocking = true
            print("[Session] Applied STRICT shields (whitelist: \(BlocklistStore.shared.whitelistCount) app(s))")
        } else {
            let personal = BlocklistStore.shared.selection
            guard BlocklistStore.shared.hasSelection else {
                print("[Session] No blocklist configured — skipping shield")
                return
            }
            BlockingManager.shared.block(selection: personal)
            didApplyBlocking = true
            print("[Session] Applied personal shields")
        }

        if let endDate = session.endDate {
            scheduleBackgroundMonitoring(until: endDate, selection: BlocklistStore.shared.selection)
        }
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
        await ExtensionAuthTokenBridge.persistIDTokenForExtension(forcingRefresh: true)
        persistActiveSessionContext(for: session)

        if statusChanged || !didApplyBlocking {
            applyLocalBlocking(for: session)
        }
        if let endDate = session.endDate, scheduledEndDate != endDate {
            scheduleBackgroundMonitoring(until: endDate, selection: BlocklistStore.shared.selection)
            scheduledEndDate = endDate
        } else if statusChanged, session.endDate == nil {
            scheduleBackgroundMonitoring(
                until: Date().addingTimeInterval(TimeInterval(session.durationMin * 60)),
                selection: BlocklistStore.shared.selection
            )
        }
        startCountdown(for: session)
        await flushPendingOpenedEvents()
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
        countdownTask?.cancel()

        guard let endDate = session.endDate else {
            secondsRemaining = session.durationMin * 60
            return
        }

        updateRemainingSeconds(until: endDate)

        countdownTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }

                await MainActor.run {
                    guard let session = self.session, session.status == .active else { return }
                    guard let endDate = session.endDate else { return }

                    self.updateRemainingSeconds(until: endDate)

                    if self.secondsRemaining <= 0 {
                        self.countdownTask?.cancel()
                        Task {
                            if self.isHost {
                                _ = await self.endSession()
                            } else {
                                if let s = self.session {
                                    self.handleSessionEnd(for: s)
                                }
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
