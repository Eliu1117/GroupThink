//
//  SessionViewModel.swift
//  Screen time demo
//
//  Owns the live session for a single group: lobby -> active -> ended, local
//  blocking, countdown, presence, and stat recording.
//

import Combine
import FirebaseFirestore
import Foundation
import SwiftUI

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var session: StudySession?
    @Published private(set) var timeRemaining: Int = 0
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let group: StudyGroup
    private let uid: String
    private let displayName: String

    private var listener: ListenerRegistration?
    private var ticker: AnyCancellable?
    private var lastStatus: SessionStatus?
    private var recordedSessionId: String?

    init(group: StudyGroup, uid: String, displayName: String) {
        self.group = group
        self.uid = uid
        self.displayName = displayName
    }

    var groupId: String { group.id ?? "" }
    var myUid: String { uid }
    var isHost: Bool { session?.hostUid == uid }
    var isParticipant: Bool { session?.participants[uid] != nil }
    var myState: ParticipantState? { session?.participants[uid]?.state }

    // MARK: - Lifecycle

    func start() {
        guard let groupId = group.id else { return }
        listener?.remove()
        listener = SessionService.shared.observeCurrentSession(groupId: groupId) { [weak self] session in
            Task { @MainActor in self?.apply(session) }
        }
        startTicker()
    }

    func stop() {
        listener?.remove()
        listener = nil
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - Host actions

    func createSession(durationMin: Int) async {
        guard let groupId = group.id else { return }
        await run {
            _ = try await SessionService.shared.createSession(
                groupId: groupId,
                hostUid: self.uid,
                hostName: self.displayName,
                durationMin: durationMin,
                blockedAppCount: BlocklistStore.shared.selectedCount
            )
        }
    }

    func activateSession() async {
        guard let groupId = group.id, let sessionId = session?.id else { return }
        await run {
            try await SessionService.shared.activateSession(groupId: groupId, sessionId: sessionId)
        }
    }

    func endSession() async {
        guard let groupId = group.id, let sessionId = session?.id else { return }
        await run {
            try await SessionService.shared.endSession(groupId: groupId, sessionId: sessionId)
        }
    }

    // MARK: - Member actions

    func joinSession() async {
        guard let groupId = group.id, let sessionId = session?.id else { return }
        await run {
            try await SessionService.shared.joinSession(
                groupId: groupId,
                sessionId: sessionId,
                uid: self.uid,
                displayName: self.displayName
            )
        }
    }

    /// Leaving early during an active session marks the user as `.left` for the group to see.
    func leaveEarly() async {
        guard
            let groupId = group.id,
            let sessionId = session?.id,
            session?.status == .active,
            myState == .focused
        else { return }
        try? await SessionService.shared.updateParticipantState(
            groupId: groupId, sessionId: sessionId, uid: uid, state: .left
        )
    }

    /// Called when the app changes scene phase.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            Task { await leaveEarly() }
        case .active:
            Task { await reportOpenedBlockedAppIfNeeded() }
        default:
            break
        }
    }

    /// The monitor extension flags when a blocked app was opened (it can't reach Firebase).
    /// On returning to the foreground we forward that to the group via Firestore.
    private func reportOpenedBlockedAppIfNeeded() async {
        let defaults = UserDefaults(suiteName: StudyHallShared.appGroupID)
        guard defaults?.bool(forKey: "presence.openedBlockedApp") == true else { return }
        defaults?.removeObject(forKey: "presence.openedBlockedApp")

        guard
            let groupId = group.id,
            let sessionId = session?.id,
            session?.status == .active,
            isParticipant
        else { return }
        try? await SessionService.shared.updateParticipantState(
            groupId: groupId, sessionId: sessionId, uid: uid, state: .opened
        )
    }

    // MARK: - Reacting to session state

    private func apply(_ newSession: StudySession?) {
        let previousStatus = lastStatus
        session = newSession
        lastStatus = newSession?.status

        guard let newSession else {
            BlockingManager.shared.stopScheduledSession()
            return
        }

        switch newSession.status {
        case .lobby:
            break
        case .active:
            // Apply local blocking once when entering the active state as a participant.
            if previousStatus != .active, isParticipant {
                applyLocalBlocking(durationMin: remainingMinutes(for: newSession))
            }
        case .ended:
            if previousStatus != .ended {
                finishSession(newSession)
            }
        }
        updateTimeRemaining()
    }

    private func applyLocalBlocking(durationMin: Int) {
        let selection = BlocklistStore.shared.selection
        guard durationMin > 0, BlocklistStore.shared.hasSelection else { return }
        do {
            try BlockingManager.shared.startScheduledSession(selection: selection, durationMin: durationMin)
        } catch {
            // Fall back to an in-app shield if scheduling is unavailable (e.g. no extension yet).
            BlockingManager.shared.block(selection: selection)
        }
    }

    private func finishSession(_ session: StudySession) {
        BlockingManager.shared.stopScheduledSession()
        guard isParticipant, myState == .focused, recordedSessionId != session.id else { return }
        recordedSessionId = session.id
        let minutes = session.durationMin
        Task {
            try? await UserService.shared.recordCompletedSession(uid: uid, focusMinutes: minutes)
        }
    }

    private func remainingMinutes(for session: StudySession) -> Int {
        guard let endAt = session.endAt else { return session.durationMin }
        return max(0, Int(ceil(endAt.timeIntervalSinceNow / 60)))
    }

    // MARK: - Countdown

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateTimeRemaining() }
    }

    private func updateTimeRemaining() {
        guard let session, session.status == .active, let endAt = session.endAt else {
            timeRemaining = 0
            return
        }
        let remaining = Int(endAt.timeIntervalSinceNow)
        timeRemaining = max(0, remaining)

        // Host clears the session when the timer elapses so everyone unblocks.
        if remaining <= 0, isHost {
            Task { await endSession() }
        }
    }

    // MARK: - Helpers

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        listener?.remove()
        ticker?.cancel()
    }
}
