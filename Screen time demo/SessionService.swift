//
//  SessionService.swift
//  Screen time demo
//
//  Firestore reads/writes for the group's single active-session slot:
//  `groups/{groupId}/sessions/current`.
//
//  Each new session overwrites this document (setData) and embeds a fresh
//  UUID in the `sessionId` field. This eliminates per-session document
//  creation/deletion costs and makes the path predictable for both the
//  SDK and the extension REST layer.
//

import FirebaseFirestore
import Foundation

enum SessionServiceError: LocalizedError {
    case notSignedIn
    case sessionAlreadyActive
    case notHost
    case notCreator
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You must be signed in to manage sessions."
        case .sessionAlreadyActive:
            return "This group already has an active study hall session."
        case .notHost:
            return "Only the session host can perform this action."
        case .notCreator:
            return "Only the group creator can delete this group."
        case .sessionNotFound:
            return "Session not found."
        }
    }
}

final class SessionService {
    static let shared = SessionService()

    private let db = Firestore.firestore()

    private init() {}

    /// The single session slot for a group. All sessions share this document path;
    /// the embedded `sessionId` UUID distinguishes them for stats idempotency.
    private func activeSessionRef(for groupID: String) -> DocumentReference {
        db.collection("groups").document(groupID).collection("sessions").document("current")
    }

    // MARK: - Observe

    /// Listens on the group's single session slot. Emits the session when its
    /// status is `lobby` or `active`; emits `nil` for `ended` or a missing document.
    func observeLiveSession(
        groupID: String,
        onChange: @escaping (Result<StudySession?, Error>) -> Void
    ) -> ListenerRegistration {
        activeSessionRef(for: groupID).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }

            guard
                let snapshot,
                snapshot.exists,
                let session = StudySession(document: snapshot),
                session.status != .ended
            else {
                onChange(.success(nil))
                return
            }

            onChange(.success(session))
        }
    }

    // MARK: - Create

    func createSession(
        groupID: String,
        hostUID: String,
        durationMin: Int = 25,
        strictMode: Bool = false,
        breakVotingEnabled: Bool = false,
        breakWindowSeconds: Int = 120,
        breakCooldownMinutes: Int = 0,
        totalSessionsInCycle: Int = 1, // GRO-40: back-to-back (Pomodoro) session count
        pomodoroConfiguration: PomodoroConfiguration = .defaults
    ) async throws -> String {
        let ref = activeSessionRef(for: groupID)

        // Cheap single-document read — no collection query or index scan needed.
        let existing = try await ref.getDocument()
        if existing.exists,
           let statusRaw = existing.data()?["status"] as? String,
           let status = SessionStatus(rawValue: statusRaw),
           status == .lobby || status == .active {
            throw SessionServiceError.sessionAlreadyActive
        }

        let sessionID = UUID().uuidString
        let cycleID = UUID().uuidString
        let data: [String: Any] = [
            "sessionId": sessionID,
            "status": SessionStatus.lobby.rawValue,
            "hostUid": hostUID,
            "durationMin": durationMin,
            "strictMode": strictMode,
            "participants": [
                hostUID: ["state": ParticipantState.focused.rawValue],
            ],
            // GRO-11: break voting snapshot (copied from group settings at creation time)
            "breakVotingEnabled": breakVotingEnabled,
            "breakWindowSeconds": breakWindowSeconds,
            "breakCooldownMinutes": breakCooldownMinutes,
            // GRO-40: back-to-back (Pomodoro) cycle bookkeeping.
            "cycleId": cycleID,
            "totalSessionsInCycle": max(1, totalSessionsInCycle),
            "currentSessionIndex": 1,
        ].merging(pomodoroConfiguration.firestoreFields) { _, new in new }

        try await ref.setData(data)
        print("[Firestore Session] Started session \(sessionID) in group \(groupID) (strict: \(strictMode), breakVoting: \(breakVotingEnabled), cycle: 1/\(max(1, totalSessionsInCycle)))")
        return sessionID
    }

    // MARK: - Back-to-back cycle advancement (GRO-40)

    /// Overwrites the session slot with the NEXT sub-session in a back-to-back cycle once
    /// the inter-session break finishes. Keeps `cycleId`/duration/settings, issues a fresh
    /// `sessionId` + `startAt`, resets every participant to `focused`, and — since this uses
    /// `setData` rather than `updateData` — implicitly clears break/vote state left over from
    /// the previous sub-session (no explicit `FieldValue.delete()` needed).
    func advanceToNextSessionInCycle(groupID: String, hostUID: String) async throws {
        let ref = activeSessionRef(for: groupID)
        let snapshot = try await ref.getDocument()

        guard let session = StudySession(document: snapshot) else {
            throw SessionServiceError.sessionNotFound
        }
        guard session.hostUid == hostUID else {
            throw SessionServiceError.notHost
        }

        let resetParticipants: [String: Any] = Dictionary(
            uniqueKeysWithValues: session.participants.keys.map { uid in
                (uid, ["state": ParticipantState.focused.rawValue])
            }
        )
        let nextIndex = session.currentSessionIndex + 1

        let data: [String: Any] = [
            "sessionId": UUID().uuidString,
            "status": SessionStatus.active.rawValue,
            "hostUid": session.hostUid,
            "durationMin": session.durationMin,
            "strictMode": session.strictMode,
            "startAt": FieldValue.serverTimestamp(),
            "participants": resetParticipants,
            "breakVotingEnabled": session.breakVotingEnabled,
            "breakWindowSeconds": session.breakWindowSeconds,
            "breakCooldownMinutes": session.breakCooldownMinutes,
            "cycleId": session.cycleId,
            "totalSessionsInCycle": session.totalSessionsInCycle,
            "currentSessionIndex": nextIndex,
        ].merging(session.pomodoroConfiguration.firestoreFields) { _, new in new }

        try await ref.setData(data)
        print("[Firestore Session] Cycle \(session.cycleId) advanced to sub-session \(nextIndex)/\(session.totalSessionsInCycle) in group \(groupID)")
    }

    // MARK: - Join

    func joinSession(groupID: String, userUID: String) async throws {
        try await activeSessionRef(for: groupID).updateData([
            "participants.\(userUID)": ["state": ParticipantState.focused.rawValue],
        ])
        print("[Firestore Session] User \(userUID) joined session")
    }

    // MARK: - Launch

    func launchSession(groupID: String, hostUID: String) async throws {
        let ref = activeSessionRef(for: groupID)
        let snapshot = try await ref.getDocument()

        guard let session = StudySession(document: snapshot) else {
            throw SessionServiceError.sessionNotFound
        }

        guard session.hostUid == hostUID else {
            throw SessionServiceError.notHost
        }

        try await ref.updateData([
            "status": SessionStatus.active.rawValue,
            "startAt": FieldValue.serverTimestamp(),
        ])
        print("[Firestore Session] Launched session \(session.id)")
    }

    // MARK: - Participant state

    func updateParticipantState(
        groupID: String,
        userUID: String,
        state: ParticipantState
    ) async throws {
        try await activeSessionRef(for: groupID).updateData([
            "participants.\(userUID).state": state.rawValue,
        ])
        print("[Firestore Session] Updated \(userUID) state to \(state.rawValue)")
    }

    // MARK: - Presence (Phase 4)

    /// Real-time listener on the session slot's `participants` map.
    func observeSessionParticipants(
        groupID: String,
        onChange: @escaping (Result<[String: ParticipantState], Error>) -> Void
    ) -> ListenerRegistration {
        activeSessionRef(for: groupID).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }

            guard let snapshot, snapshot.exists else {
                onChange(.success([:]))
                return
            }

            onChange(.success(Self.parseParticipants(from: snapshot)))
        }
    }

    /// Writes the authenticated user's presence state to `participants.{uid}.state`.
    func updatePresence(
        groupID: String,
        userUID: String,
        state: ParticipantState
    ) async throws {
        try await updateParticipantState(groupID: groupID, userUID: userUID, state: state)
        print("[Firestore Presence] Updated \(userUID) → \(state.rawValue)")
    }

    func markFocused(groupID: String, userUID: String) async throws {
        try await updatePresence(groupID: groupID, userUID: userUID, state: .focused)
    }

    func markLeft(groupID: String, userUID: String) async throws {
        try await updatePresence(groupID: groupID, userUID: userUID, state: .left)
    }

    func markOpened(groupID: String, userUID: String) async throws {
        try await updatePresence(groupID: groupID, userUID: userUID, state: .opened)
    }

    static func parseParticipants(from document: DocumentSnapshot) -> [String: ParticipantState] {
        guard let data = document.data(),
              let participantsMap = data["participants"] as? [String: Any]
        else {
            return [:]
        }

        var parsed: [String: ParticipantState] = [:]
        for (uid, value) in participantsMap {
            if let participantData = value as? [String: Any],
               let stateRaw = participantData["state"] as? String,
               let state = ParticipantState(rawValue: stateRaw) {
                parsed[uid] = state
            }
        }
        return parsed
    }

    // MARK: - Break lifecycle (GRO-35 / GRO-40)

    /// Writes the break start timestamp to the session document.
    /// Only the host may call this; other clients detect the break via their Firestore listener.
    /// GRO-40: `durationSec` lets back-to-back cycles pass a Pomodoro-computed break length
    /// (standard vs. long); callers that don't care fall back to the original 10-minute default.
    func startBreak(groupID: String, hostUID: String, durationSec: Int = 600) async throws {
        let ref = activeSessionRef(for: groupID)
        let snapshot = try await ref.getDocument()
        guard let session = StudySession(document: snapshot) else { throw SessionServiceError.sessionNotFound }
        guard session.hostUid == hostUID else { throw SessionServiceError.notHost }

        try await ref.updateData([
            "breakStartedAt": FieldValue.serverTimestamp(),
            "breakDurationSec": max(1, durationSec),
            "breakPausedSecondsRemaining": 0,
        ])
        print("[Break] Break started in group \(groupID) (\(durationSec)s)")
    }

    /// Pauses the break countdown, freezing it at `secondsRemaining`.
    func pauseBreak(groupID: String, hostUID: String, secondsRemaining: Int) async throws {
        let ref = activeSessionRef(for: groupID)
        let snapshot = try await ref.getDocument()
        guard let session = StudySession(document: snapshot) else { throw SessionServiceError.sessionNotFound }
        guard session.hostUid == hostUID else { throw SessionServiceError.notHost }

        try await ref.updateData([
            "breakPausedAt": FieldValue.serverTimestamp(),
            "breakPausedSecondsRemaining": max(0, secondsRemaining),
        ])
        print("[Break] Break paused at \(secondsRemaining)s in group \(groupID)")
    }

    /// Resumes a paused break, writing a new start timestamp and duration.
    func resumeBreak(groupID: String, hostUID: String, secondsRemaining: Int) async throws {
        let ref = activeSessionRef(for: groupID)
        let snapshot = try await ref.getDocument()
        guard let session = StudySession(document: snapshot) else { throw SessionServiceError.sessionNotFound }
        guard session.hostUid == hostUID else { throw SessionServiceError.notHost }

        var update: [String: Any] = [
            "breakStartedAt": FieldValue.serverTimestamp(),
            "breakDurationSec": max(1, secondsRemaining),
            "breakPausedSecondsRemaining": 0,
        ]
        update["breakPausedAt"] = FieldValue.delete()
        try await ref.updateData(update)
        print("[Break] Break resumed with \(secondsRemaining)s in group \(groupID)")
    }

    // MARK: - End

    /// Verifies the caller is the host then marks the session `ended`.
    /// The slot document stays in place so the next session can overwrite it cheaply.
    /// GRO-40: `cycleEndedEarly` should be true only when the host cut a back-to-back
    /// cycle short while sessions/breaks still remained — a natural finish of the last
    /// sub-session (or a single, non-cycle session) leaves it false.
    func endSession(groupID: String, requesterUID: String, cycleEndedEarly: Bool = false) async throws {
        let ref = activeSessionRef(for: groupID)
        let snapshot = try await ref.getDocument()

        guard let session = StudySession(document: snapshot) else {
            throw SessionServiceError.sessionNotFound
        }

        guard session.hostUid == requesterUID else {
            throw SessionServiceError.notHost
        }

        var update: [String: Any] = ["status": SessionStatus.ended.rawValue]
        if cycleEndedEarly {
            update["cycleEndedEarly"] = true
        }
        try await ref.updateData(update)
        print("[Firestore Session] Marked session \(session.id) ended in group \(groupID)\(cycleEndedEarly ? " (cycle ended early)" : "")")
    }
}
