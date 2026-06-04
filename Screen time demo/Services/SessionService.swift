//
//  SessionService.swift
//  Screen time demo
//
//  Reads/writes for `groups/{groupId}/sessions`.
//

import FirebaseFirestore
import Foundation

final class SessionService {
    static let shared = SessionService()

    private let db = Firestore.firestore()

    private init() {}

    private func sessions(in groupId: String) -> CollectionReference {
        db.collection("groups").document(groupId).collection("sessions")
    }

    /// Host creates a session in the `lobby` state and joins it.
    func createSession(
        groupId: String,
        hostUid: String,
        hostName: String,
        durationMin: Int,
        blockedAppCount: Int
    ) async throws -> String {
        let ref = sessions(in: groupId).document()
        let session = StudySession(
            id: ref.documentID,
            hostUid: hostUid,
            durationMin: durationMin,
            status: .lobby,
            blockedAppCount: blockedAppCount,
            participants: [
                hostUid: ParticipantInfo(displayName: hostName, state: .focused, joinedAt: Date())
            ]
        )
        try ref.setData(from: session)
        return ref.documentID
    }

    func joinSession(groupId: String, sessionId: String, uid: String, displayName: String) async throws {
        try await sessions(in: groupId).document(sessionId).updateData([
            "participants.\(uid)": [
                "displayName": displayName,
                "state": ParticipantState.focused.rawValue,
                "joinedAt": FieldValue.serverTimestamp()
            ]
        ])
    }

    /// Host flips the session to `active` and stamps the start time.
    func activateSession(groupId: String, sessionId: String) async throws {
        try await sessions(in: groupId).document(sessionId).updateData([
            "status": SessionStatus.active.rawValue,
            "startAt": FieldValue.serverTimestamp()
        ])
    }

    func endSession(groupId: String, sessionId: String) async throws {
        try await sessions(in: groupId).document(sessionId).updateData([
            "status": SessionStatus.ended.rawValue
        ])
    }

    func updateParticipantState(
        groupId: String,
        sessionId: String,
        uid: String,
        state: ParticipantState
    ) async throws {
        try await sessions(in: groupId).document(sessionId).updateData([
            "participants.\(uid).state": state.rawValue
        ])
    }

    func observeSession(
        groupId: String,
        sessionId: String,
        onChange: @escaping (StudySession?) -> Void
    ) -> ListenerRegistration {
        sessions(in: groupId).document(sessionId).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: StudySession.self))
        }
    }

    /// Observes the most recent session that is still in `lobby` or `active`,
    /// so members landing on the group screen see an in-progress study hall.
    func observeCurrentSession(
        groupId: String,
        onChange: @escaping (StudySession?) -> Void
    ) -> ListenerRegistration {
        sessions(in: groupId)
            .whereField("status", in: [SessionStatus.lobby.rawValue, SessionStatus.active.rawValue])
            .limit(to: 1)
            .addSnapshotListener { snapshot, _ in
                let session = snapshot?.documents.first.flatMap { try? $0.data(as: StudySession.self) }
                onChange(session)
            }
    }
}
