//
//  DowntimeOverrideRequest.swift
//  Screen time demo
//
//  Stored at `groups/{groupID}/downtimeOverrides/{requestID}`.
//  Represents a peer-approved temporary exemption from downtime blocking.
//

import FirebaseFirestore
import Foundation

enum DowntimeOverrideStatus: String, Equatable {
    case pending
    case approved
    case denied
    case expired
}

struct DowntimeOverrideRequest: Identifiable, Equatable {
    let id: String
    /// Group that owns this request.
    let groupID: String
    /// UID of the member who needs the override.
    let requestorUID: String
    let requestedAt: Date
    /// How long the override should last once approved (1, 15, or custom minutes).
    let durationMinutes: Int
    var status: DowntimeOverrideStatus
    /// UID of the peer who responded.
    var responderUID: String?
    var respondedAt: Date?
    /// Populated when approved — requestor's device uses this to know when to re-block.
    var expiresAt: Date?

    // MARK: - Firestore deserialisation

    init?(groupID: String, id: String, map: [String: Any]) {
        guard
            let requestorUID = map["requestorUID"] as? String,
            let requestedAtTS = map["requestedAt"] as? Timestamp,
            let durationMinutes = map["durationMinutes"] as? Int,
            let statusRaw = map["status"] as? String,
            let status = DowntimeOverrideStatus(rawValue: statusRaw)
        else { return nil }

        self.id = id
        self.groupID = groupID
        self.requestorUID = requestorUID
        self.requestedAt = requestedAtTS.dateValue()
        self.durationMinutes = durationMinutes
        self.status = status
        self.responderUID = map["responderUID"] as? String
        self.respondedAt = (map["respondedAt"] as? Timestamp)?.dateValue()
        self.expiresAt = (map["expiresAt"] as? Timestamp)?.dateValue()
    }

    func asMap() -> [String: Any] {
        var map: [String: Any] = [
            "requestorUID": requestorUID,
            "requestedAt": FieldValue.serverTimestamp(),
            "durationMinutes": durationMinutes,
            "status": status.rawValue,
        ]
        if let responderUID { map["responderUID"] = responderUID }
        if let respondedAt { map["respondedAt"] = Timestamp(date: respondedAt) }
        if let expiresAt { map["expiresAt"] = Timestamp(date: expiresAt) }
        return map
    }

    // MARK: - Computed

    /// True if an approved override has passed its expiry time.
    var isExpired: Bool {
        guard status == .approved, let exp = expiresAt else { return false }
        return Date() > exp
    }

    /// Friendly duration label e.g. "1 min", "15 min".
    var durationLabel: String {
        durationMinutes == 1 ? "1 min" : "\(durationMinutes) min"
    }
}
