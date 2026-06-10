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

    // MARK: - Phase 5 streak fields
    /// Consecutive days on which every member completed a session.
    let currentGroupStreak: Int
    /// Calendar day the group streak was last counted.
    let lastGroupStreakUpdate: Date?

    // MARK: - GRO-9/14/20 settings
    /// When true, the host's personal blocklist is enforced on all participants at session start.
    let enforceHostBlocks: Bool
    /// When true, users may join a session that is already in the active state.
    let allowLateJoin: Bool
    /// When true, only the group creator can start a new session.
    let creatorOnlyStart: Bool

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
        self.enforceHostBlocks = data["enforceHostBlocks"] as? Bool ?? true
        self.allowLateJoin = data["allowLateJoin"] as? Bool ?? true
        self.creatorOnlyStart = data["creatorOnlyStart"] as? Bool ?? true
    }

    init(
        id: String,
        name: String,
        inviteCode: String,
        createdBy: String,
        memberUids: [String],
        currentGroupStreak: Int = 0,
        lastGroupStreakUpdate: Date? = nil,
        enforceHostBlocks: Bool = true,
        allowLateJoin: Bool = true,
        creatorOnlyStart: Bool = true
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.memberUids = memberUids
        self.currentGroupStreak = currentGroupStreak
        self.lastGroupStreakUpdate = lastGroupStreakUpdate
        self.enforceHostBlocks = enforceHostBlocks
        self.allowLateJoin = allowLateJoin
        self.creatorOnlyStart = creatorOnlyStart
    }

    /// Generates a short, human-friendly invite code (ambiguous characters omitted).
    static func generateInviteCode(length: Int = 6) -> String {
        let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
