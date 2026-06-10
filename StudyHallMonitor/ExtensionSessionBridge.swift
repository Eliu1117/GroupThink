//
//  ExtensionSessionBridge.swift
//  StudyHallMonitor
//
//  App Group fallback queue when direct extension Firestore writes are unavailable.
//

import Foundation

private enum BridgeKeys {
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    static let activeSessionContextKey = "studyHall.activeSessionContext"
    static let pendingOpenedEventsKey = "studyHall.pendingOpenedEvents"
    static let currentGroupIdKey = "currentGroupId"
    static let currentSessionIdKey = "currentSessionId"
    static let currentUserIdKey = "currentUserId"
}

private struct ActiveSessionContext: Codable {
    let groupID: String
    let sessionID: String
    let userUID: String
}

private struct PendingOpenedEvent: Codable {
    let groupID: String
    let sessionID: String
    let userUID: String
    let recordedAt: Date
}

enum ExtensionSessionBridge {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: BridgeKeys.appGroupID)
    }

    static func handleBlockedAppOpened() {
        ExtensionFirebaseWriter.markOpenedFromBackground()
    }

    static func enqueuePendingOpenedFallback() {
        guard let context = loadActiveSession() else {
            print("[DeviceActivity Monitor] No active session context — skipping opened fallback queue")
            return
        }

        enqueuePendingOpened(for: context)
        print("[DeviceActivity Monitor] Queued opened fallback for \(context.userUID)")
    }

    private static func loadActiveSession() -> ActiveSessionContext? {
        guard let defaults else { return nil }

        if let data = defaults.data(forKey: BridgeKeys.activeSessionContextKey),
           let context = try? JSONDecoder().decode(ActiveSessionContext.self, from: data) {
            return context
        }

        guard
            let groupID = defaults.string(forKey: BridgeKeys.currentGroupIdKey),
            let sessionID = defaults.string(forKey: BridgeKeys.currentSessionIdKey),
            let userUID = defaults.string(forKey: BridgeKeys.currentUserIdKey)
        else {
            return nil
        }

        return ActiveSessionContext(groupID: groupID, sessionID: sessionID, userUID: userUID)
    }

    private static func enqueuePendingOpened(for context: ActiveSessionContext) {
        guard let defaults else { return }

        var events: [PendingOpenedEvent] = []
        if let data = defaults.data(forKey: BridgeKeys.pendingOpenedEventsKey),
           let decoded = try? JSONDecoder().decode([PendingOpenedEvent].self, from: data) {
            events = decoded
        }

        let event = PendingOpenedEvent(
            groupID: context.groupID,
            sessionID: context.sessionID,
            userUID: context.userUID,
            recordedAt: Date()
        )

        if !events.contains(where: { $0.groupID == event.groupID && $0.sessionID == event.sessionID && $0.userUID == event.userUID }) {
            events.append(event)
        }

        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: BridgeKeys.pendingOpenedEventsKey)
        defaults.synchronize()
    }
}
