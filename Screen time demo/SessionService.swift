//
//  SessionService.swift
//  Screen time demo
//
//  Firestore reads/writes for `groups/{groupId}/sessions`.
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

    private func sessions(for groupID: String) -> CollectionReference {
        db.collection("groups").document(groupID).collection("sessions")
    }

    // MARK: - Observe

    /// Listens for the group's current lobby or active session (at most one).
    func observeLiveSession(
        groupID: String,
        onChange: @escaping (Result<StudySession?, Error>) -> Void
    ) -> ListenerRegistration {
        sessions(for: groupID)
            .whereField("status", in: [SessionStatus.lobby.rawValue, SessionStatus.active.rawValue])
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }

                guard let document = snapshot?.documents.first else {
                    onChange(.success(nil))
                    return
                }

                let session = StudySession(id: document.documentID, document: document)
                onChange(.success(session))
            }
    }

    // MARK: - Create

    func createSession(
        groupID: String,
        hostUID: String,
        durationMin: Int = 25
    ) async throws -> String {
        let existing = try await sessions(for: groupID)
            .whereField("status", in: [SessionStatus.lobby.rawValue, SessionStatus.active.rawValue])
            .limit(to: 1)
            .getDocuments()

        guard existing.documents.isEmpty else {
            throw SessionServiceError.sessionAlreadyActive
        }

        let ref = sessions(for: groupID).document()
        let data: [String: Any] = [
            "status": SessionStatus.lobby.rawValue,
            "hostUid": hostUID,
            "durationMin": durationMin,
            "blocklistConfig": [:] as [String: Any],
            "participants": [
                hostUID: ["state": ParticipantState.focused.rawValue],
            ],
        ]

        try await ref.setData(data)
        print("[Firestore Session] Created session \(ref.documentID) in group \(groupID)")
        return ref.documentID
    }

    // MARK: - Join

    func joinSession(groupID: String, sessionID: String, userUID: String) async throws {
        let ref = sessions(for: groupID).document(sessionID)
        try await ref.updateData([
            "participants.\(userUID)": ["state": ParticipantState.focused.rawValue],
        ])
        print("[Firestore Session] User \(userUID) joined session \(sessionID)")
    }

    // MARK: - Launch

    func launchSession(groupID: String, sessionID: String, hostUID: String) async throws {
        let ref = sessions(for: groupID).document(sessionID)
        let snapshot = try await ref.getDocument()

        guard let session = StudySession(id: snapshot.documentID, document: snapshot) else {
            throw SessionServiceError.sessionNotFound
        }

        guard session.hostUid == hostUID else {
            throw SessionServiceError.notHost
        }

        try await ref.updateData([
            "status": SessionStatus.active.rawValue,
            "startAt": FieldValue.serverTimestamp(),
        ])
        print("[Firestore Session] Launched session \(sessionID)")
    }

    // MARK: - Participant state

    func updateParticipantState(
        groupID: String,
        sessionID: String,
        userUID: String,
        state: ParticipantState
    ) async throws {
        let ref = sessions(for: groupID).document(sessionID)
        try await ref.updateData([
            "participants.\(userUID).state": state.rawValue,
        ])
        print("[Firestore Session] Updated \(userUID) state to \(state.rawValue)")
    }

    // MARK: - Presence (Phase 4)

    /// Real-time listener on a specific session document's `participants` map.
    func observeSessionParticipants(
        groupID: String,
        sessionID: String,
        onChange: @escaping (Result<[String: ParticipantState], Error>) -> Void
    ) -> ListenerRegistration {
        sessions(for: groupID)
            .document(sessionID)
            .addSnapshotListener { snapshot, error in
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
        sessionID: String,
        userUID: String,
        state: ParticipantState
    ) async throws {
        try await updateParticipantState(
            groupID: groupID,
            sessionID: sessionID,
            userUID: userUID,
            state: state
        )
        print("[Firestore Presence] Updated \(userUID) → \(state.rawValue)")
    }

    func markFocused(groupID: String, sessionID: String, userUID: String) async throws {
        try await updatePresence(groupID: groupID, sessionID: sessionID, userUID: userUID, state: .focused)
    }

    func markLeft(groupID: String, sessionID: String, userUID: String) async throws {
        try await updatePresence(groupID: groupID, sessionID: sessionID, userUID: userUID, state: .left)
    }

    func markOpened(groupID: String, sessionID: String, userUID: String) async throws {
        try await updatePresence(groupID: groupID, sessionID: sessionID, userUID: userUID, state: .opened)
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

    // MARK: - End

    /// Verifies the caller is the host then permanently deletes the session document.
    /// All listeners drop to nil immediately, triggering local teardown on every device.
    func endSession(groupID: String, sessionID: String, requesterUID: String) async throws {
        let ref = sessions(for: groupID).document(sessionID)
        let snapshot = try await ref.getDocument()

        guard let session = StudySession(id: snapshot.documentID, document: snapshot) else {
            throw SessionServiceError.sessionNotFound
        }

        guard session.hostUid == requesterUID else {
            throw SessionServiceError.notHost
        }

        try await ref.delete()
        print("[Firestore Session] Deleted session document \(sessionID) in group \(groupID)")
    }
}
