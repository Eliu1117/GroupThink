//
//  ExtensionSessionBridge.swift
//  ExtensionSupport
//
//  App Group fallback queue when direct extension Firestore writes are unavailable.
//

import Foundation

private enum BridgeKeys {
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    static let pendingOpenedEventsKey = "studyHall.pendingOpenedEvents"
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

    static func enqueuePendingOpenedFallback() {
        guard let context = ExtensionSessionContext.load() else {
            print("[Extension] No active session context — skipping opened fallback queue")
            return
        }

        enqueuePendingOpened(for: context)
        print("[Extension] Queued opened fallback for \(context.userUID)")
    }

    private static func enqueuePendingOpened(for context: ExtensionSessionContext) {
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
