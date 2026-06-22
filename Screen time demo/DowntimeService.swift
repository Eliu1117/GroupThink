//
//  DowntimeService.swift
//  Screen time demo
//
//  Reads/writes downtime schedules (per user) and peer override requests (per group).
//

import FamilyControls
import FirebaseFirestore
import Foundation

enum DowntimeServiceError: LocalizedError {
    case scheduleNotFound
    case overrideAlreadyPending
    case notGroupMember
    case cannotApproveOwnRequest

    var errorDescription: String? {
        switch self {
        case .scheduleNotFound: return "No downtime schedule found."
        case .overrideAlreadyPending: return "You already have a pending override request."
        case .notGroupMember: return "Only group members can respond to override requests."
        case .cannotApproveOwnRequest: return "You cannot approve your own override request."
        }
    }
}

final class DowntimeService {
    static let shared = DowntimeService()
    private let db = Firestore.firestore()
    private init() {}

    private func userRef(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func overridesRef(groupID: String) -> CollectionReference {
        db.collection("groups").document(groupID).collection("downtimeOverrides")
    }

    // MARK: - Schedule

    /// Persists the user's downtime schedule to Firestore and caches the
    /// enabled state in App Group UserDefaults for the monitor extension.
    func saveSchedule(uid: String, schedule: DowntimeSchedule) async throws {
        // Use setData(merge:) so this works whether or not the user doc already exists.
        try await userRef(uid).setData(["downtime": schedule.asMap()], merge: true)

        // Cache enabled flag for extension reads.
        if let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID) {
            shared.set(schedule.enabled, forKey: "studyHall.downtimeScheduleEnabled")
        }

        print("[Downtime] Saved schedule for \(uid): \(schedule.formattedStart()) – \(schedule.formattedEnd())")
    }

    /// Loads the user's stored downtime schedule from Firestore.
    func loadSchedule(uid: String) async throws -> DowntimeSchedule {
        let snap = try await userRef(uid).getDocument()
        guard
            let data = snap.data(),
            let map = data["downtime"] as? [String: Any],
            let schedule = DowntimeSchedule(map: map)
        else {
            return .default
        }
        return schedule
    }

    /// Caches the user's downtime allowed-apps selection in App Group UserDefaults
    /// so the monitor extension can read it without Firestore access.
    func persistAllowedApps(_ selection: FamilyActivitySelection) {
        guard
            let data = try? PropertyListEncoder().encode(selection),
            let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID)
        else { return }
        shared.set(data, forKey: StudyHallConstants.downtimeAllowedAppsKey)
        print("[Downtime] Cached allowed apps (\(selection.applicationTokens.count) apps)")
    }

    /// Loads the cached allowed-apps selection from App Group UserDefaults.
    func loadAllowedApps() -> FamilyActivitySelection {
        guard
            let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID),
            let data = shared.data(forKey: StudyHallConstants.downtimeAllowedAppsKey),
            let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    // MARK: - Override requests

    /// Submits a new downtime override request. Throws if one is already pending.
    func submitOverrideRequest(
        groupID: String,
        requestorUID: String,
        durationMinutes: Int
    ) async throws {
        // Guard: no existing pending request from this user.
        let existing = try await overridesRef(groupID: groupID)
            .whereField("requestorUID", isEqualTo: requestorUID)
            .whereField("status", isEqualTo: DowntimeOverrideStatus.pending.rawValue)
            .getDocuments()

        guard existing.documents.isEmpty else {
            throw DowntimeServiceError.overrideAlreadyPending
        }

        let ref = overridesRef(groupID: groupID).document()
        let request = DowntimeOverrideRequest(
            groupID: groupID,
            id: ref.documentID,
            map: [
                "requestorUID": requestorUID,
                "requestedAt": Timestamp(date: Date()),
                "durationMinutes": durationMinutes,
                "status": DowntimeOverrideStatus.pending.rawValue,
            ]
        )
        try await ref.setData(request?.asMap() ?? [
            "requestorUID": requestorUID,
            "requestedAt": FieldValue.serverTimestamp(),
            "durationMinutes": durationMinutes,
            "status": DowntimeOverrideStatus.pending.rawValue,
        ])

        print("[Downtime] Override request submitted by \(requestorUID) for \(durationMinutes) min")
    }

    /// Approves or denies a pending override request.
    /// On approval the `expiresAt` is calculated server-side (now + durationMinutes).
    func respondToOverrideRequest(
        groupID: String,
        requestID: String,
        approved: Bool,
        responderUID: String
    ) async throws {
        let ref = overridesRef(groupID: groupID).document(requestID)

        let snap = try await ref.getDocument()
        guard let data = snap.data() else { return }
        guard let requestorUID = data["requestorUID"] as? String else { return }

        guard responderUID != requestorUID else {
            throw DowntimeServiceError.cannotApproveOwnRequest
        }

        let status: DowntimeOverrideStatus = approved ? .approved : .denied
        var update: [String: Any] = [
            "status": status.rawValue,
            "responderUID": responderUID,
            "respondedAt": FieldValue.serverTimestamp(),
        ]

        if approved, let durationMinutes = data["durationMinutes"] as? Int {
            let expiresAt = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
            update["expiresAt"] = Timestamp(date: expiresAt)
        }

        try await ref.updateData(update)
        print("[Downtime] Override request \(requestID) \(approved ? "approved" : "denied") by \(responderUID)")
    }

    /// Real-time listener for all pending + recent override requests in a group.
    func observeOverrideRequests(
        groupID: String,
        onChange: @escaping ([DowntimeOverrideRequest]) -> Void
    ) -> ListenerRegistration {
        overridesRef(groupID: groupID)
            .order(by: "requestedAt", descending: true)
            .limit(to: 20)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("[Downtime] Override listener error: \(error.localizedDescription)")
                    return
                }
                let requests = snapshot?.documents.compactMap { doc in
                    DowntimeOverrideRequest(groupID: groupID, id: doc.documentID, map: doc.data())
                } ?? []
                onChange(requests)
            }
    }

    /// Marks a request as expired if it has passed its `expiresAt` timestamp.
    func expireOverrideRequestIfNeeded(groupID: String, requestID: String) async {
        let ref = overridesRef(groupID: groupID).document(requestID)
        do {
            try await ref.updateData(["status": DowntimeOverrideStatus.expired.rawValue])
            print("[Downtime] Override \(requestID) expired")
        } catch {
            print("[Downtime] Could not expire override \(requestID): \(error.localizedDescription)")
        }
    }
}
