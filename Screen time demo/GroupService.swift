//
//  GroupService.swift
//  Screen time demo
//
//  Firestore reads/writes for the `groups` collection.
//

import FirebaseFirestore
import Foundation

enum GroupServiceError: LocalizedError {
    case invalidInviteCode
    case alreadyMember
    case notSignedIn
    case notCreator

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode:
            return "No group found for that invite code."
        case .alreadyMember:
            return "You're already a member of this group."
        case .notSignedIn:
            return "You must be signed in to manage groups."
        case .notCreator:
            return "Only the group creator can delete this group."
        }
    }
}

final class GroupService {
    static let shared = GroupService()

    private let db = Firestore.firestore()

    private init() {}

    private var groups: CollectionReference {
        db.collection("groups")
    }

    // MARK: - Create

    /// Creates a group and returns its document ID.
    func createGroup(name: String, creatorUID: String) async throws -> String {
        let ref = groups.document()
        let inviteCode = try await uniqueInviteCode()

        let data: [String: Any] = [
            "name": name,
            "inviteCode": inviteCode,
            "createdBy": creatorUID,
            "memberUids": [creatorUID],
            // Default group settings
            "strictMode": false,
            "requireBlocklist": true,
            "allowLateJoin": true,
            "creatorOnlyStart": true,
            "lastSessionDurationMin": 25,
        ]

        try await ref.setData(data)
        return ref.documentID
    }

    // MARK: - Join

    /// Finds a group by invite code and atomically adds the user to `memberUids`.
    @discardableResult
    func joinGroup(inviteCode: String, userUID: String) async throws -> Group {
        let normalized = inviteCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalized.isEmpty else {
            throw GroupServiceError.invalidInviteCode
        }

        let snapshot = try await groups
            .whereField("inviteCode", isEqualTo: normalized)
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first else {
            throw GroupServiceError.invalidInviteCode
        }

        guard let group = Group(id: document.documentID, document: document) else {
            throw GroupServiceError.invalidInviteCode
        }

        guard !group.memberUids.contains(userUID) else {
            throw GroupServiceError.alreadyMember
        }

        try await document.reference.updateData([
            "memberUids": FieldValue.arrayUnion([userUID]),
        ])

        return Group(
            id: group.id,
            name: group.name,
            inviteCode: group.inviteCode,
            createdBy: group.createdBy,
            memberUids: group.memberUids + [userUID]
        )
    }

    // MARK: - Listen

    /// Real-time listener for groups the user belongs to.
    func observeGroups(
        for userUID: String,
        onChange: @escaping (Result<[Group], Error>) -> Void
    ) -> ListenerRegistration {
        groups
            .whereField("memberUids", arrayContains: userUID)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }

                let groups = snapshot?.documents.compactMap { doc in
                    Group(id: doc.documentID, document: doc)
                } ?? []

                let sorted = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                onChange(.success(sorted))
            }
    }

    /// Real-time listener for a single group document (live settings, streaks, roster).
    func observeGroup(
        groupID: String,
        onChange: @escaping (Result<Group?, Error>) -> Void
    ) -> ListenerRegistration {
        groups.document(groupID).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }

            guard let snapshot, snapshot.exists else {
                onChange(.success(nil))
                return
            }

            onChange(.success(Group(id: snapshot.documentID, document: snapshot)))
        }
    }

    // MARK: - Break vote cross-session penalty (GRO-11)

    /// Called when a break vote passes to flag that the next session must start penalty-locked.
    func markBreakPassed(groupID: String) async throws {
        try await groups.document(groupID).updateData(["breakPassedLastSession": true])
        print("[Groups] breakPassedLastSession set to true for group \(groupID)")
    }

    /// Called at the start of a new session to consume the cross-session penalty flag.
    func clearBreakPenalty(groupID: String) async throws {
        try await groups.document(groupID).updateData(["breakPassedLastSession": false])
        print("[Groups] breakPassedLastSession cleared for group \(groupID)")
    }

    // MARK: - Session duration (GRO-33)

    /// Records the last-used session duration on the group document so all members'
    /// start-session pickers stay in sync. No creator check — any session host may update this.
    func updateLastSessionDuration(groupID: String, durationMin: Int) async throws {
        try await groups.document(groupID).updateData(["lastSessionDurationMin": durationMin])
        print("[Groups] lastSessionDurationMin set to \(durationMin) for group \(groupID)")
    }

    // MARK: - Settings

    /// Updates a single Bool group setting. Only the creator may change settings.
    func updateGroupSetting(
        groupID: String,
        requesterUID: String,
        key: String,
        value: Bool
    ) async throws {
        try await performSettingUpdate(groupID: groupID, requesterUID: requesterUID, key: key, value: value)
    }

    /// Updates a single Int group setting (e.g. defaultSessionDurationMin). Only the creator may change settings.
    func updateGroupSetting(
        groupID: String,
        requesterUID: String,
        key: String,
        value: Int
    ) async throws {
        try await performSettingUpdate(groupID: groupID, requesterUID: requesterUID, key: key, value: value)
    }

    private func performSettingUpdate(
        groupID: String,
        requesterUID: String,
        key: String,
        value: Any
    ) async throws {
        let ref = groups.document(groupID)
        let snapshot = try await ref.getDocument()

        guard let group = Group(id: snapshot.documentID, document: snapshot) else {
            throw GroupServiceError.invalidInviteCode
        }

        guard group.createdBy == requesterUID else {
            throw GroupServiceError.notCreator
        }

        try await ref.updateData([key: value])
        print("[Groups] Updated setting \(key) = \(value) on group \(groupID)")
    }

    // MARK: - Members

    /// Resolves member UIDs to display names from `users/{uid}`.
    func fetchMemberDisplayNames(for uids: [String]) async throws -> [String: String] {
        await UserService.shared.fetchDisplayNames(for: uids)
    }

    // MARK: - Delete

    /// Deletes a group and its sessions subcollection. Only the creator may delete.
    func deleteGroup(groupID: String, requesterUID: String) async throws {
        let ref = groups.document(groupID)
        let snapshot = try await ref.getDocument()

        guard let group = Group(id: snapshot.documentID, document: snapshot) else {
            throw GroupServiceError.invalidInviteCode
        }

        guard group.createdBy == requesterUID else {
            throw GroupServiceError.notCreator
        }

        let sessionsSnapshot = try await ref.collection("sessions").getDocuments()
        let batch = db.batch()

        for document in sessionsSnapshot.documents {
            batch.deleteDocument(document.reference)
        }

        batch.deleteDocument(ref)
        try await batch.commit()
        print("[Groups] Deleted group \(groupID) and \(sessionsSnapshot.documents.count) session(s)")
    }

    // MARK: - Helpers

    private func uniqueInviteCode() async throws -> String {
        for _ in 0..<5 {
            let code = Group.generateInviteCode()
            let existing = try await groups
                .whereField("inviteCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()

            if existing.documents.isEmpty {
                return code
            }
        }

        return Group.generateInviteCode(length: 8)
    }
}
