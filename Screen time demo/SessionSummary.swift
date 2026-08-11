//
//  SessionSummary.swift
//  Screen time demo
//
//  Snapshot of a finished session, built locally the moment the session ends.
//  Drives the post-session summary screen and end-of-session notification.
//

import Foundation

struct SessionSummary: Identifiable, Equatable {
    /// Session UUID — also used as sheet identity.
    let id: String
    let groupName: String
    let durationMin: Int
    let startAt: Date?
    let endedAt: Date
    /// Final presence states for every participant.
    let participants: [SessionParticipant]
    /// Display names snapshot at session end.
    let memberNames: [String: String]
    let myUID: String
    /// Final state of the local user.
    let myState: ParticipantState?
    /// Focus minutes the local user earned this session (0 if they didn't stay focused).
    /// GRO-40: for a back-to-back cycle this is the CUMULATIVE total across every
    /// sub-session, not just the final one.
    let minutesEarned: Int
    let wasStrictMode: Bool

    // MARK: - Back-to-back / Pomodoro cycle (GRO-40)
    /// Total sub-sessions planned for this cycle (1 for a plain, non-cycle session).
    let totalSessionsInCycle: Int
    /// 1-based index of the sub-session that was active/just-finished when the cycle ended.
    let completedSessionIndex: Int
    /// True when the host cut the cycle short before all planned sessions/breaks ran.
    let cycleEndedEarly: Bool

    init(
        id: String,
        groupName: String,
        durationMin: Int,
        startAt: Date?,
        endedAt: Date,
        participants: [SessionParticipant],
        memberNames: [String: String],
        myUID: String,
        myState: ParticipantState?,
        minutesEarned: Int,
        wasStrictMode: Bool,
        totalSessionsInCycle: Int = 1,
        completedSessionIndex: Int = 1,
        cycleEndedEarly: Bool = false
    ) {
        self.id = id
        self.groupName = groupName
        self.durationMin = durationMin
        self.startAt = startAt
        self.endedAt = endedAt
        self.participants = participants
        self.memberNames = memberNames
        self.myUID = myUID
        self.myState = myState
        self.minutesEarned = minutesEarned
        self.wasStrictMode = wasStrictMode
        self.totalSessionsInCycle = max(1, totalSessionsInCycle)
        self.completedSessionIndex = max(1, completedSessionIndex)
        self.cycleEndedEarly = cycleEndedEarly
    }

    /// True when this summarizes a multi-session cycle rather than a single session.
    var isPomodoroCycle: Bool { totalSessionsInCycle > 1 }

    var focusedCount: Int { participants.filter { $0.state == .focused }.count }
    var leftCount: Int { participants.filter { $0.state == .left }.count }
    var openedCount: Int { participants.filter { $0.state == .opened }.count }

    /// Minutes the session actually ran (host may end early).
    var actualMinutes: Int {
        guard let startAt else { return durationMin }
        let elapsed = Int((endedAt.timeIntervalSince(startAt) / 60).rounded())
        return min(durationMin, max(elapsed, 0))
    }

    var iStayedFocused: Bool { myState == .focused }

    /// Participants ordered: focused first, then alphabetically.
    var rankedParticipants: [SessionParticipant] {
        participants.sorted { lhs, rhs in
            let rankL = Self.rank(lhs.state)
            let rankR = Self.rank(rhs.state)
            if rankL != rankR { return rankL < rankR }
            return (memberNames[lhs.id] ?? lhs.id) < (memberNames[rhs.id] ?? rhs.id)
        }
    }

    private static func rank(_ state: ParticipantState) -> Int {
        switch state {
        case .focused: return 0
        case .break: return 1
        case .left: return 2
        case .opened: return 3
        }
    }
}
