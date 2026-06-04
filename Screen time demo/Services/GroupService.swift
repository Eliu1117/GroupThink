//
//  GroupService.swift
//  Screen time demo
//
//  Reads/writes for the `groups` collection.
//

import FirebaseFirestore
import Foundation

enum GroupServiceError: LocalizedError {
    case invalidInviteCode
    case alreadyMember

    var errorDescription: String? {
        switch self {
        case .invalidInviteCode: return "No group found for that invite code."
        case .alreadyMember: return "You're already a member of this group."
        }
    }
}

final class GroupService {
    static let shared = GroupService()

    private let db = Firestore.firestore()
    private var groups: CollectionReference { db.collection("groups") }

    private init() {}

    /// Creates a new group with a unique invite code and returns its id.
    func createGroup(name: String, ownerUid: String) async throws -> String {
        let ref = groups.document()
        let group = StudyGroup(
            id: ref.documentID,
            name: name,
            memberUids: [ownerUid],
            inviteCode: try await uniqueInviteCode(),
            createdBy: ownerUid,
            createdAt: Date()
        )
        try ref.setData(from: group)
        return ref.documentID
    }

    /// Adds the user to the group matching `inviteCode`. Returns the joined group.
    @discardableResult
    func joinGroup(inviteCode: String, uid: String) async throws -> StudyGroup {
        let normalized = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let snapshot = try await groups
            .whereField("inviteCode", isEqualTo: normalized)
            .limit(to: 1)
            .getDocuments()

        guard let document = snapshot.documents.first else {
            throw GroupServiceError.invalidInviteCode
        }

        let group = try document.data(as: StudyGroup.self)
        guard !group.memberUids.contains(uid) else {
            throw GroupServiceError.alreadyMember
        }

        try await document.reference.updateData([
            "memberUids": FieldValue.arrayUnion([uid])
        ])
        return group
    }

    func leaveGroup(groupId: String, uid: String) async throws {
        try await groups.document(groupId).updateData([
            "memberUids": FieldValue.arrayRemove([uid])
        ])
    }

    func observeGroups(for uid: String, onChange: @escaping ([StudyGroup]) -> Void) -> ListenerRegistration {
        groups
            .whereField("memberUids", arrayContains: uid)
            .addSnapshotListener { snapshot, _ in
                let result = snapshot?.documents.compactMap { try? $0.data(as: StudyGroup.self) } ?? []
                onChange(result)
            }
    }

    func observeGroup(groupId: String, onChange: @escaping (StudyGroup?) -> Void) -> ListenerRegistration {
        groups.document(groupId).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: StudyGroup.self))
        }
    }

    func bumpGroupStreak(groupId: String, to value: Int) async throws {
        try await groups.document(groupId).updateData(["groupStreak": value])
    }

    private func uniqueInviteCode() async throws -> String {
        for _ in 0..<5 {
            let code = StudyGroup.makeInviteCode()
            let existing = try await groups
                .whereField("inviteCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()
            if existing.documents.isEmpty { return code }
        }
        // Extremely unlikely fallback: append more entropy.
        return StudyGroup.makeInviteCode(length: 8)
    }
}
