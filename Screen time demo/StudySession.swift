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
}
