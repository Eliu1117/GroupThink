//
//  SessionContextStore.swift
//  Screen time demo
//
//  App Group bridge for active session metadata and extension-queued presence events.
//

import Foundation

struct ActiveSessionContext: Codable, Equatable {
    let groupID: String
    let sessionID: String
    let userUID: String
}

struct PendingOpenedEvent: Codable, Equatable {
    let groupID: String
    let sessionID: String
    let userUID: String
    let recordedAt: Date
}

final class SessionContextStore {
    static let shared = SessionContextStore()

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: StudyHallConstants.appGroupID)
    }

    private init() {}

    func setActiveSession(_ context: ActiveSessionContext?) {
        guard let defaults else { return }

        if let context {
            if let data = try? JSONEncoder().encode(context) {
                defaults.set(data, forKey: StudyHallConstants.activeSessionContextKey)
            }

            // Flat keys for lightweight extension reads before background Firestore writes.
            defaults.set(context.groupID, forKey: StudyHallConstants.currentGroupIdKey)
            defaults.set(context.sessionID, forKey: StudyHallConstants.currentSessionIdKey)
            defaults.set(context.userUID, forKey: StudyHallConstants.currentUserIdKey)
            defaults.synchronize()

            print("[SessionContext] Saved active session \(context.sessionID) for user \(context.userUID)")
        } else {
            clearFlatSessionKeys()
            defaults.removeObject(forKey: StudyHallConstants.activeSessionContextKey)
            defaults.synchronize()
            print("[SessionContext] Cleared active session context")
        }
    }

    func activeSession() -> ActiveSessionContext? {
        if let defaults,
           let data = defaults.data(forKey: StudyHallConstants.activeSessionContextKey),
           let context = try? JSONDecoder().decode(ActiveSessionContext.self, from: data) {
            return context
        }

        return loadFlatSessionContext()
    }

    func enqueuePendingOpened(for context: ActiveSessionContext) {
        guard let defaults else { return }

        var events = pendingOpenedEvents()
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
        defaults.set(data, forKey: StudyHallConstants.pendingOpenedEventsKey)
        defaults.synchronize()
        print("[SessionContext] Queued opened event for \(context.userUID)")
    }

    func pendingOpenedEvents() -> [PendingOpenedEvent] {
        guard
            let defaults,
            let data = defaults.data(forKey: StudyHallConstants.pendingOpenedEventsKey),
            let events = try? JSONDecoder().decode([PendingOpenedEvent].self, from: data)
        else {
            return []
        }
        return events
    }

    @discardableResult
    func drainPendingOpenedEvents() -> [PendingOpenedEvent] {
        let events = pendingOpenedEvents()
        defaults?.removeObject(forKey: StudyHallConstants.pendingOpenedEventsKey)
        defaults?.synchronize()
        return events
    }

    // MARK: - Strict mode flag (read by StudyHallMonitor extension)

    func setStrictMode(_ isStrict: Bool) {
        defaults?.set(isStrict, forKey: StudyHallConstants.strictModeKey)
        defaults?.synchronize()
    }

    func clearAll() {
        setActiveSession(nil)
        defaults?.removeObject(forKey: StudyHallConstants.pendingOpenedEventsKey)
        defaults?.removeObject(forKey: StudyHallConstants.firebaseIdTokenKey)
        defaults?.removeObject(forKey: StudyHallConstants.firebaseIdTokenExpiryKey)
        defaults?.removeObject(forKey: StudyHallConstants.lastOpenedReportKey)
        defaults?.removeObject(forKey: StudyHallConstants.lastOpenedReportAtKey)
        defaults?.set(false, forKey: StudyHallConstants.strictModeKey)
        defaults?.synchronize()
    }

    // MARK: - Private

    private func loadFlatSessionContext() -> ActiveSessionContext? {
        guard
            let defaults,
            let groupID = defaults.string(forKey: StudyHallConstants.currentGroupIdKey),
            let sessionID = defaults.string(forKey: StudyHallConstants.currentSessionIdKey),
            let userUID = defaults.string(forKey: StudyHallConstants.currentUserIdKey)
        else {
            return nil
        }

        return ActiveSessionContext(groupID: groupID, sessionID: sessionID, userUID: userUID)
    }

    private func clearFlatSessionKeys() {
        guard let defaults else { return }
        defaults.removeObject(forKey: StudyHallConstants.currentGroupIdKey)
        defaults.removeObject(forKey: StudyHallConstants.currentSessionIdKey)
        defaults.removeObject(forKey: StudyHallConstants.currentUserIdKey)
    }
}
