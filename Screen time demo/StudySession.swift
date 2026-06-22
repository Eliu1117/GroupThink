//
//  StudySession.swift
//  Screen time demo
//
//  Firestore document model for `groups/{groupId}/sessions/{sessionId}`.
//

import FirebaseFirestore
import Foundation

enum SessionStatus: String, Equatable {
    case lobby
    case active
    case ended
}

enum ParticipantState: String, Equatable, CaseIterable {
    case focused
    case `break`
    case left
    case opened

    var label: String {
        switch self {
        case .focused: return "Focused"
        case .break: return "On Break"
        case .left: return "Left Early"
        case .opened: return "Opened App"
        }
    }

    var systemImage: String {
        switch self {
        case .focused: return "checkmark.circle.fill"
        case .break: return "cup.and.saucer.fill"
        case .left: return "figure.walk.departure"
        case .opened: return "exclamationmark.triangle.fill"
        }
    }

    /// Phase 4 presence states written by the app and extension.
    static let presenceStates: [ParticipantState] = [.focused, .left, .opened]
}

struct SessionParticipant: Identifiable, Equatable {
    let id: String
    let state: ParticipantState
}

struct StudySession: Identifiable, Equatable {
    let id: String
    let status: SessionStatus
    let hostUid: String
    let durationMin: Int
    let startAt: Date?
    let participants: [String: ParticipantState]
    /// Strict mode snapshot taken from the group at session creation: every member's
    /// device blocks ALL apps except their personal whitelist for the session duration.
    let strictMode: Bool

    // MARK: - Break voting (GRO-11)
    /// Whether break voting is enabled for this session (copied from group at creation).
    let breakVotingEnabled: Bool
    /// Voting window duration in seconds (copied from group at creation).
    let breakWindowSeconds: Int
    /// Cooldown between votes in minutes. 0 = use default (ceil(0.20 × durationMin)).
    let breakCooldownMinutes: Int
    /// Timestamp when the most recent vote concluded (passed, failed, or expired).
    /// Used to enforce the per-session cooldown.
    let lastBreakVoteEndedAt: Date?
    /// Set to true when a break vote has already passed in this session.
    /// Prevents early-end votes from passing again in the same session.
    let penaltyLock: Bool
    /// The currently active break vote, or nil when no vote is in flight.
    let activeBreakVote: BreakVote?

    // MARK: - Break state (GRO-35)
    /// When non-nil, a group break is in progress. The countdown is computed from this
    /// timestamp so it survives navigation and app restarts on all devices.
    let breakStartedAt: Date?
    /// Total break seconds granted when the break began (or when it was most recently resumed).
    let breakDurationSec: Int
    /// When non-nil the break is currently paused; the countdown must not tick.
    let breakPausedAt: Date?
    /// Seconds remaining at the moment the break was paused. Used to seed the countdown on resume.
    let breakPausedSecondsRemaining: Int

    /// Initialises from the well-known `sessions/current` document.
    /// `id` is taken from the stored `sessionId` UUID field so stats idempotency
    /// works across session resets without relying on the document's Firestore ID.
    init?(document: DocumentSnapshot) {
        guard document.exists, let data = document.data() else { return nil }

        guard
            let statusRaw = data["status"] as? String,
            let status = SessionStatus(rawValue: statusRaw),
            let hostUid = data["hostUid"] as? String,
            let durationMin = data["durationMin"] as? Int
        else {
            return nil
        }

        // Prefer the stored UUID; fall back to documentID for legacy random-ID docs.
        self.id = (data["sessionId"] as? String) ?? document.documentID
        self.status = status
        self.hostUid = hostUid
        self.durationMin = durationMin
        self.strictMode = data["strictMode"] as? Bool ?? false

        // Break voting
        self.breakVotingEnabled = data["breakVotingEnabled"] as? Bool ?? false
        self.breakWindowSeconds = data["breakWindowSeconds"] as? Int ?? 120
        self.breakCooldownMinutes = data["breakCooldownMinutes"] as? Int ?? 0
        self.penaltyLock = data["penaltyLock"] as? Bool ?? false
        self.lastBreakVoteEndedAt = (data["lastBreakVoteEndedAt"] as? Timestamp)?.dateValue()
        if let voteMap = data["activeBreakVote"] as? [String: Any] {
            activeBreakVote = BreakVote(map: voteMap)
        } else {
            activeBreakVote = nil
        }

        // Break state (GRO-35)
        self.breakStartedAt = (data["breakStartedAt"] as? Timestamp)?.dateValue()
        self.breakDurationSec = data["breakDurationSec"] as? Int ?? 600
        self.breakPausedAt = (data["breakPausedAt"] as? Timestamp)?.dateValue()
        self.breakPausedSecondsRemaining = data["breakPausedSecondsRemaining"] as? Int ?? 0

        if let timestamp = data["startAt"] as? Timestamp {
            startAt = timestamp.dateValue()
        } else {
            startAt = nil
        }

        var parsedParticipants: [String: ParticipantState] = [:]
        if let participantsMap = data["participants"] as? [String: Any] {
            for (uid, value) in participantsMap {
                if let participantData = value as? [String: Any],
                   let stateRaw = participantData["state"] as? String,
                   let state = ParticipantState(rawValue: stateRaw) {
                    parsedParticipants[uid] = state
                }
            }
        }
        participants = parsedParticipants
    }

    var participantList: [SessionParticipant] {
        participants
            .map { SessionParticipant(id: $0.key, state: $0.value) }
            .sorted { $0.id < $1.id }
    }

    var endDate: Date? {
        guard let startAt else { return nil }
        return startAt.addingTimeInterval(TimeInterval(durationMin * 60))
    }

    // MARK: - Break state helpers (GRO-35)

    /// True while a group-approved break is in progress (running or paused).
    var breakIsActive: Bool { breakStartedAt != nil }

    /// True while the break is paused.
    var breakIsPaused: Bool { breakPausedAt != nil }

    /// Seconds remaining in the current break, computed from Firestore timestamps.
    /// Returns 0 when no break is active.
    var computedBreakSecondsRemaining: Int {
        guard let start = breakStartedAt else { return 0 }
        if breakPausedAt != nil {
            return max(0, breakPausedSecondsRemaining)
        }
        let elapsed = Int(Date().timeIntervalSince(start))
        return max(0, breakDurationSec - elapsed)
    }

    // MARK: - Break vote gate checks (GRO-11)
    /// Cooldown period in minutes, resolved from the stored value or the 20 % default.
    var effectiveBreakCooldownMinutes: Int {
        breakCooldownMinutes > 0
            ? breakCooldownMinutes
            : max(1, Int(ceil(Double(durationMin) * 0.20)))
    }

    /// True once 50 % of the session has elapsed — required before a vote can start.
    var breakTimeLockCleared: Bool {
        guard let startAt else { return false }
        let halfwayPoint = startAt.addingTimeInterval(TimeInterval(durationMin * 60) * 0.5)
        return Date() >= halfwayPoint
    }

    /// True when the cooldown since the last vote has elapsed (or no vote has occurred).
    var breakCooldownCleared: Bool {
        guard let lastEnd = lastBreakVoteEndedAt else { return true }
        let cooldownEnd = lastEnd.addingTimeInterval(TimeInterval(effectiveBreakCooldownMinutes * 60))
        return Date() >= cooldownEnd
    }

    /// True when all four pre-conditions for initiating a break vote are met.
    var canInitiateBreakVote: Bool {
        breakVotingEnabled
            && status == .active
            && breakTimeLockCleared
            && breakCooldownCleared
            && (activeBreakVote == nil || !activeBreakVote!.isPending)
            && !penaltyLock
    }
}
