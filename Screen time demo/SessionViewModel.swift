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

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var session: StudySession?
    @Published private(set) var participants: [SessionParticipant] = []
    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?

    private var groupID: String?
    private var currentUID: String?
    private var sessionListener: ListenerRegistration?
    private var countdownTask: Task<Void, Never>?
    private var didApplyBlocking = false
    private var previousStatus: SessionStatus?
    private var scheduledEndDate: Date?
    private var isTearingDown = false

    deinit {
        sessionListener?.remove()
        countdownTask?.cancel()
    }

    func configure(groupID: String, currentUID: String?) {
        guard self.groupID != groupID || self.currentUID != currentUID else { return }

        stopListening()
        self.groupID = groupID
        self.currentUID = currentUID
        session = nil
        participants = []
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

    func stopListening() {
        detachSessionListener()
        haltLocalSessionInfrastructure(reason: "listener stop")
    }

    // MARK: - Actions

    func createSession(durationMin: Int = 25) async -> Bool {
        guard let groupID, let currentUID else {
            errorMessage = SessionServiceError.notSignedIn.localizedDescription
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await SessionService.shared.createSession(
                groupID: groupID,
                hostUID: currentUID,
                durationMin: durationMin
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

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await SessionService.shared.joinSession(
                groupID: groupID,
                sessionID: session.id,
                userUID: currentUID
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error joining lobby: \(error.localizedDescription)")
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
                sessionID: session.id,
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
                sessionID: session.id,
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
                    sessionID: event.sessionID,
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
                sessionID: sessionID,
                requesterUID: currentUID
            )
            awardStats(for: activeSession)
            detachSessionListener()
            self.session = nil
            participants = []
            previousStatus = nil
            print("[Firestore Session] Session \(sessionID) ended — local state cleared")
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
                awardStats(for: session)
                finalizeSessionTeardown(clearSessionDocument: true)
            }
        } else {
            // The live-session query drops the doc once it ends, so the listener
            // reports nil. Award from the last known active snapshot.
            if previousStatus == .active, let lastSession = self.session {
                awardStats(for: lastSession)
            }
            finalizeSessionTeardown(clearSessionDocument: true)
        }
    }

    /// Phase 5 — awards focus minutes and records violations for the LOCAL user.
    /// Focused users earn full elapsed minutes; opened-app users earn 0 minutes
    /// but a violation count. Idempotent per session (guarded inside StatsService).
    private func awardStats(for session: StudySession) {
        guard let groupID, let currentUID else { return }

        let state = session.participants[currentUID]
        let violated = state == .opened

        let focusMinutes: Int
        if state == .focused, let startAt = session.startAt {
            let elapsed = Int((Date().timeIntervalSince(startAt) / 60).rounded())
            focusMinutes = min(session.durationMin, max(elapsed, 0))
        } else {
            focusMinutes = 0
        }

        guard focusMinutes > 0 || violated else {
            print("[Stats] No award — local user left or was not a participant")
            return
        }

        let sessionID = session.id
        Task {
            await StatsService.shared.recordSessionCompletion(
                groupID: groupID,
                sessionID: sessionID,
                userUID: currentUID,
                focusMinutes: focusMinutes,
                violated: violated
            )
        }
    }

    private func applyLocalBlocking(for session: StudySession) {
        let selection = BlocklistStore.shared.selection
        guard BlocklistStore.shared.hasSelection else {
            print("[Firestore Session] No local blocklist configured — skipping shield")
            return
        }

        BlockingManager.shared.block(selection: selection)
        didApplyBlocking = true
        print("[Firestore Session] Applied local app shields")

        if let endDate = session.endDate {
            scheduleBackgroundMonitoring(until: endDate, selection: selection)
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
                                if let session = self.session {
                                    self.awardStats(for: session)
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
            print("[Firestore Session] Cleared local blocking — \(reason)")
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

        print("[Firestore Session] Re-attaching listener after failed end")
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
}
