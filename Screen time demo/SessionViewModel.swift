//
//  SessionViewModel.swift
//  Screen time demo
//
//  Real-time session state, countdown, and local blocking for a group study hall.
//

import Combine
import FirebaseFirestore
import Foundation

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var session: StudySession?
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
        sessionListener?.remove()
        sessionListener = nil
        countdownTask?.cancel()
        countdownTask = nil

        if didApplyBlocking {
            BlockingManager.shared.clear()
            SessionActivityScheduler.stopMonitoring()
            didApplyBlocking = false
            print("[Firestore Session] Cleared local blocking on listener stop")
        }
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
        guard let groupID, let currentUID, let session, session.status == .active else { return }

        do {
            try await SessionService.shared.updateParticipantState(
                groupID: groupID,
                sessionID: session.id,
                userUID: currentUID,
                state: state
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error updating user state: \(error.localizedDescription)")
        }
    }

    func endSession() async -> Bool {
        guard let groupID, let currentUID, let session else { return false }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await SessionService.shared.endSession(
                groupID: groupID,
                sessionID: session.id,
                requesterUID: currentUID
            )
            clearLocalSessionState()
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Firestore Session] Error ending session: \(error.localizedDescription)")
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
        if let session {
            let statusChanged = previousStatus != session.status
            previousStatus = session.status
            self.session = session

            switch session.status {
            case .lobby:
                stopCountdown()
                SessionActivityScheduler.stopMonitoring()
                scheduledEndDate = nil
                if didApplyBlocking {
                    BlockingManager.shared.clear()
                    didApplyBlocking = false
                }

            case .active:
                if statusChanged || !didApplyBlocking {
                    applyLocalBlocking(for: session)
                }
                if let endDate = session.endDate, scheduledEndDate != endDate {
                    scheduleBackgroundMonitoring(until: endDate)
                    scheduledEndDate = endDate
                }
                startCountdown(for: session)

            case .ended:
                clearLocalSessionState()
            }
        } else {
            self.session = nil
            previousStatus = nil
            clearLocalSessionState()
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
            scheduleBackgroundMonitoring(until: endDate)
        }
    }

    private func scheduleBackgroundMonitoring(until endDate: Date) {
        do {
            try SessionActivityScheduler.startMonitoring(until: endDate)
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
                            } else if self.didApplyBlocking {
                                BlockingManager.shared.clear()
                                SessionActivityScheduler.stopMonitoring()
                                self.didApplyBlocking = false
                                print("[Firestore Session] Timer expired — cleared local blocking")
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

    private func clearLocalSessionState() {
        stopCountdown()
        secondsRemaining = 0
        scheduledEndDate = nil
        SessionActivityScheduler.stopMonitoring()
        if didApplyBlocking {
            BlockingManager.shared.clear()
            SessionActivityScheduler.stopMonitoring()
            didApplyBlocking = false
            print("[Firestore Session] Cleared local blocking — session ended")
        }

        if session?.status == .ended {
            session = nil
            previousStatus = nil
        }
    }
}
