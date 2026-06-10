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
    let minutesEarned: Int
    let wasStrictMode: Bool

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
