//
//  StudySession.swift
//  Screen time demo
//
//  Firestore document model for `groups/{groupId}/sessions/{sessionId}`.
//

import FirebaseFirestore
import Foundation

enum SessionStatus: String, Codable {
    case lobby
    case active
    case ended
}

enum ParticipantState: String, Codable {
    case focused
    case left
    case opened
}

struct ParticipantInfo: Codable {
    var displayName: String
    var state: ParticipantState
    var joinedAt: Date?

    init(displayName: String, state: ParticipantState = .focused, joinedAt: Date? = nil) {
        self.displayName = displayName
        self.state = state
        self.joinedAt = joinedAt
    }
}

struct StudySession: Codable, Identifiable {
    @DocumentID var id: String?
    var hostUid: String
    var startAt: Date?
    var durationMin: Int
    var status: SessionStatus
    /// How many apps/categories the host chose to block. Stored for display only —
    /// each member blocks their own locally chosen apps (Family Controls tokens are
    /// device-specific and not portable between phones).
    var blockedAppCount: Int
    var participants: [String: ParticipantInfo]

    init(
        id: String? = nil,
        hostUid: String,
        startAt: Date? = nil,
        durationMin: Int,
        status: SessionStatus = .lobby,
        blockedAppCount: Int = 0,
        participants: [String: ParticipantInfo] = [:]
    ) {
        self.id = id
        self.hostUid = hostUid
        self.startAt = startAt
        self.durationMin = durationMin
        self.status = status
        self.blockedAppCount = blockedAppCount
        self.participants = participants
    }

    /// The time the session is scheduled to end, if it has started.
    var endAt: Date? {
        guard let startAt else { return nil }
        return startAt.addingTimeInterval(TimeInterval(durationMin * 60))
    }

    /// Participants sorted by join time then name, for stable list rendering.
    var sortedParticipants: [(uid: String, info: ParticipantInfo)] {
        participants
            .map { (uid: $0.key, info: $0.value) }
            .sorted { lhs, rhs in
                switch (lhs.info.joinedAt, rhs.info.joinedAt) {
                case let (l?, r?): return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: return lhs.info.displayName < rhs.info.displayName
                }
            }
    }
}
