//
//  Group.swift
//  Screen time demo
//
//  Firestore document model for `groups/{groupId}`.
//

import FirebaseFirestore
import Foundation

struct Group: Identifiable, Equatable, Hashable {
    /// Document ID (`groupId`).
    let id: String
    let name: String
    let inviteCode: String
    let createdBy: String
    let memberUids: [String]
    /// Consecutive days on which every member completed a session (Phase 5).
    let currentGroupStreak: Int
    /// Calendar day the group streak was last counted.
    let lastGroupStreakUpdate: Date?

    init?(
        id: String,
        document: DocumentSnapshot
    ) {
        guard document.exists, let data = document.data() else { return nil }

        guard
            let name = data["name"] as? String,
            let inviteCode = data["inviteCode"] as? String,
            let createdBy = data["createdBy"] as? String,
            let memberUids = data["memberUids"] as? [String]
        else {
            return nil
        }

        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.memberUids = memberUids
        self.currentGroupStreak = data["currentGroupStreak"] as? Int ?? 0
        self.lastGroupStreakUpdate = (data["lastGroupStreakUpdate"] as? Timestamp)?.dateValue()
    }

    init(
        id: String,
        name: String,
        inviteCode: String,
        createdBy: String,
        memberUids: [String],
        currentGroupStreak: Int = 0,
        lastGroupStreakUpdate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.memberUids = memberUids
        self.currentGroupStreak = currentGroupStreak
        self.lastGroupStreakUpdate = lastGroupStreakUpdate
    }

    /// Generates a short, human-friendly invite code (ambiguous characters omitted).
    static func generateInviteCode(length: Int = 6) -> String {
        let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
