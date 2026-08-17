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

    // MARK: - Back-to-back / Pomodoro cycle (GRO-40)
    /// Shared across every sub-session belonging to the same back-to-back cycle.
    let cycleId: String
    /// Total number of consecutive sessions the host configured for this cycle (>= 1).
    let totalSessionsInCycle: Int
    /// 1-based index of the current sub-session within the cycle.
    let currentSessionIndex: Int
    /// True when the host cut the cycle short (via `endCycleEarly`) before all planned
    /// sessions/breaks ran their course.
    let cycleEndedEarly: Bool

    // MARK: - Pomodoro break settings (snapshotted at cycle start)
    let pomodoroBreakMin: Int
    /// 0 = no long breaks; otherwise every Nth inter-session break is long.
    let pomodoroLongBreakEveryN: Int
    let pomodoroLongBreakMin: Int

    var pomodoroConfiguration: PomodoroConfiguration {
        PomodoroConfiguration(
            standardBreakMin: pomodoroBreakMin,
            longBreakEnabled: pomodoroLongBreakEveryN > 0,
            longBreakEveryN: pomodoroLongBreakEveryN > 0
                ? pomodoroLongBreakEveryN
                : PomodoroConfiguration.defaultLongBreakEveryN,
            longBreakMin: pomodoroLongBreakMin
        )
    }

    /// Initialises from the well-known `sessions/current` document.
    /// `id` is taken from the stored `sessionId` UUID field so stats idempotency
    /// works across session resets without relying on the document's Firestore ID.
    ///
    /// Uses `.estimate` for server-timestamp fields (`startAt`, `breakStartedAt`, etc.) rather
    /// than the SDK default (`.none`). With `.none`, a listener's very first, locally-pending
    /// snapshot for any write that sets a `FieldValue.serverTimestamp()` field returns `nil`
    /// for that field until the server confirms it. For `breakStartedAt` in particular, that
    /// briefly made `breakIsActive` read as `false` right after starting a break, which made
    /// `SessionViewModel` think it had reverted to a plain active sub-session — re-applying
    /// shields with a now-stale (already-past) `endDate` — before the confirmed snapshot
    /// flipped it back a moment later. With very short (e.g. 1-minute testing) sessions that
    /// flicker was enough to spin the countdown/break logic into a rapid infinite loop.
    /// `.estimate` returns the local write time immediately, so these fields never appear nil.
    init?(document: DocumentSnapshot) {
        guard document.exists, let data = document.data(with: .estimate) else { return nil }

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

        // Back-to-back / Pomodoro cycle (GRO-40)
        self.cycleId = (data["cycleId"] as? String) ?? self.id
        self.totalSessionsInCycle = max(1, data["totalSessionsInCycle"] as? Int ?? 1)
        self.currentSessionIndex = max(1, data["currentSessionIndex"] as? Int ?? 1)
        self.cycleEndedEarly = data["cycleEndedEarly"] as? Bool ?? false

        let pomodoro = PomodoroConfiguration.from(sessionData: data, sessionDurationMin: durationMin)
        self.pomodoroBreakMin = pomodoro.standardBreakMin
        self.pomodoroLongBreakEveryN = pomodoro.longBreakEnabled ? pomodoro.longBreakEveryN : 0
        self.pomodoroLongBreakMin = pomodoro.longBreakMin

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

    // MARK: - Empty-session auto-end (GRO-15)

    /// True once at least one participant has joined AND every one of them is currently
    /// `.left` (backgrounded/departed) — i.e. nobody is actively focused, on a break, or
    /// mid-shield on this sub-session. Used to auto-terminate a session nobody is left in.
    var allParticipantsLeft: Bool {
        status == .active && !participants.isEmpty && participants.values.allSatisfy { $0 == .left }
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

    /// True when every pre-condition for initiating a break vote is met.
    ///
    /// GRO-45: voting eligibility is now scoped to each sub-session "block" within a
    /// back-to-back cycle rather than gated at the whole-cycle level (the old GRO-11
    /// `penaltyLock` cross-cycle rule allowed voting only in every OTHER cycle — removed).
    /// `!breakIsActive` is the one thing that disables voting "between sessions": the
    /// inter-session break itself.
    var canInitiateBreakVote: Bool {
        breakVotingEnabled
            && status == .active
            && !breakIsActive
            && breakTimeLockCleared
            && breakCooldownCleared
            && (activeBreakVote == nil || !activeBreakVote!.isPending)
    }

    // MARK: - Back-to-back / Pomodoro cycle helpers (GRO-40)

    /// True when this cycle spans more than one sub-session.
    var isPomodoroCycle: Bool { totalSessionsInCycle > 1 }

    /// True while more sub-sessions remain in the cycle after this one.
    var hasMoreSessionsInCycle: Bool { currentSessionIndex < totalSessionsInCycle }

    /// Short "Session X of Y" label for UI display during a multi-session cycle.
    var cycleProgressLabel: String { "Session \(currentSessionIndex) of \(totalSessionsInCycle)" }
}
