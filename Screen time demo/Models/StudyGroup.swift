//
//  StudyGroup.swift
//  Screen time demo
//
//  Firestore document model for `groups/{groupId}`.
//

import FirebaseFirestore
import Foundation

struct StudyGroup: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var name: String
    var memberUids: [String]
    var inviteCode: String
    var createdBy: String
    var createdAt: Date?
    var groupStreak: Int

    // Explicit conformance based on the document id avoids relying on @DocumentID's
    // synthesized Hashable, and is all navigation needs.
    static func == (lhs: StudyGroup, rhs: StudyGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(
        id: String? = nil,
        name: String,
        memberUids: [String],
        inviteCode: String,
        createdBy: String,
        createdAt: Date? = nil,
        groupStreak: Int = 0
    ) {
        self.id = id
        self.name = name
        self.memberUids = memberUids
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.groupStreak = groupStreak
    }

    /// Generates a short, human-friendly invite code with ambiguous characters removed.
    static func makeInviteCode(length: Int = 6) -> String {
        let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
