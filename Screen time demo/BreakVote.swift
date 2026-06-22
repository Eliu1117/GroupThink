//
//  BreakVote.swift
//  Screen time demo
//
//  Model for the `activeBreakVote` embedded map inside `sessions/{groupId}/current`.
//  The entire vote lifecycle lives in the session document so it stays atomic with
//  other session fields (penaltyLock, lastBreakVoteEndedAt) and is delivered in a
//  single Firestore snapshot rather than requiring a separate listener.
//

import FirebaseFirestore
import Foundation

// MARK: - Status

enum BreakVoteStatus: String, Equatable {
    case pending
    case passed
    case failed
    case expired
}

// MARK: - Model

struct BreakVote: Equatable {
    let id: String               // UUID — used to deduplicate client-side resolution writes
    let initiatorUid: String
    let startedAt: Date
    let windowSeconds: Int       // default 120
    let votes: [String: Bool]    // uid → true=for / false=against; absent uid counts as against
    let status: BreakVoteStatus

    // MARK: - Firestore decode

    /// Initialises from the `activeBreakVote` sub-map stored on the session document.
    init?(map: [String: Any]) {
        guard
            let id = map["id"] as? String,
            let initiatorUid = map["initiatorUid"] as? String,
            let startedAtTs = map["startedAt"] as? Timestamp,
            let windowSeconds = map["windowSeconds"] as? Int,
            let statusRaw = map["status"] as? String,
            let status = BreakVoteStatus(rawValue: statusRaw)
        else { return nil }

        self.id = id
        self.initiatorUid = initiatorUid
        self.startedAt = startedAtTs.dateValue()
        self.windowSeconds = windowSeconds
        self.status = status

        if let votesRaw = map["votes"] as? [String: Bool] {
            votes = votesRaw
        } else {
            votes = [:]
        }
    }

    // MARK: - Firestore encode

    func asMap() -> [String: Any] {
        [
            "id": id,
            "initiatorUid": initiatorUid,
            "startedAt": Timestamp(date: startedAt),
            "windowSeconds": windowSeconds,
            "votes": votes,
            "status": status.rawValue,
        ]
    }

    // MARK: - Computed helpers

    /// Hard deadline after which the vote expires if not resolved sooner.
    var deadline: Date {
        startedAt.addingTimeInterval(TimeInterval(windowSeconds))
    }

    /// Seconds remaining until the vote window closes.
    var secondsRemaining: Int {
        max(0, Int(deadline.timeIntervalSinceNow.rounded()))
    }

    var isPending: Bool { status == .pending }

    /// Returns true when yes-votes meet the 67 % supermajority threshold.
    /// Non-votes (absent UIDs) always count as "against".
    func hasSupermajority(totalParticipants: Int) -> Bool {
        guard totalParticipants > 0 else { return false }
        let yesCount = votes.values.filter { $0 }.count
        return Double(yesCount) / Double(totalParticipants) >= 0.67
    }
}
