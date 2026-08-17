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

    // MARK: - Group settings
    /// When true, sessions block ALL apps on each member's device except their personal whitelist.
    let strictMode: Bool
    /// When true, members must have a non-empty blocklist to start/join non-strict sessions.
    let requireBlocklist: Bool
    /// When true, users may join a session that is already in the active state.
    let allowLateJoin: Bool
    /// When true, only the group creator can start a new session.
    let creatorOnlyStart: Bool

    // MARK: - Session duration (GRO-28 / GRO-33)
    /// Duration (minutes) used in the most recent session for this group.
    /// Pre-fills the session-start picker; defaults to 25 if no session has ever been started.
    /// Firestore key: "lastSessionDurationMin".
    let lastSessionDurationMin: Int

    // MARK: - Break voting settings (GRO-11)
    /// Master toggle: when false, break voting is disabled for all sessions in this group.
    let breakVotingEnabled: Bool
    /// How long the voting window stays open in seconds (default 120).
    let breakWindowSeconds: Int
    /// Cooldown as a percentage of total session duration before another vote can start
    /// (default 20 — i.e. 20 % of 25 min = 5 min cooldown). Stored as an integer 1–100.
    let breakCooldownPercent: Int

    // MARK: - Downtime settings (GRO-12)
    /// When true, members are encouraged (and eventually enforced) to configure a nightly
    /// downtime schedule. The group feature flag lives here; the schedule itself is per-user.
    let downtimeEnabled: Bool

    // MARK: - Routine settings (GRO-13 / GRO-32)
    /// When true, members are expected to configure a routine schedule.
    /// NOTE: Firestore field key remains "morningRoutineEnabled" for backward compatibility.
    let routineEnabled: Bool

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
        self.strictMode = data["strictMode"] as? Bool ?? false
        self.requireBlocklist = data["requireBlocklist"] as? Bool ?? true
        self.allowLateJoin = data["allowLateJoin"] as? Bool ?? true
        self.creatorOnlyStart = data["creatorOnlyStart"] as? Bool ?? true
        self.breakVotingEnabled = data["breakVotingEnabled"] as? Bool ?? false
        self.breakWindowSeconds = data["breakWindowSeconds"] as? Int ?? 120
        self.breakCooldownPercent = data["breakCooldownPercent"] as? Int ?? 20
        self.lastSessionDurationMin = data["lastSessionDurationMin"] as? Int ?? 25
        self.downtimeEnabled = data["downtimeEnabled"] as? Bool ?? false
        // Reads "morningRoutineEnabled" from Firestore; Swift property is routineEnabled (GRO-32).
        self.routineEnabled = data["morningRoutineEnabled"] as? Bool ?? false
    }

    init(
        id: String,
        name: String,
        inviteCode: String,
        createdBy: String,
        memberUids: [String],
        currentGroupStreak: Int = 0,
        lastGroupStreakUpdate: Date? = nil,
        strictMode: Bool = false,
        requireBlocklist: Bool = true,
        allowLateJoin: Bool = true,
        creatorOnlyStart: Bool = true,
        breakVotingEnabled: Bool = false,
        breakWindowSeconds: Int = 120,
        breakCooldownPercent: Int = 20,
        lastSessionDurationMin: Int = 25,
        downtimeEnabled: Bool = false,
        routineEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.memberUids = memberUids
        self.currentGroupStreak = currentGroupStreak
        self.lastGroupStreakUpdate = lastGroupStreakUpdate
        self.strictMode = strictMode
        self.requireBlocklist = requireBlocklist
        self.allowLateJoin = allowLateJoin
        self.creatorOnlyStart = creatorOnlyStart
        self.breakVotingEnabled = breakVotingEnabled
        self.breakWindowSeconds = breakWindowSeconds
        self.breakCooldownPercent = breakCooldownPercent
        self.lastSessionDurationMin = lastSessionDurationMin
        self.downtimeEnabled = downtimeEnabled
        self.routineEnabled = routineEnabled
    }

    /// Generates a short, human-friendly invite code (ambiguous characters omitted).
    static func generateInviteCode(length: Int = 6) -> String {
        let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
