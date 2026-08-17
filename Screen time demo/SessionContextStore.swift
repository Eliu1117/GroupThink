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

/// Drains the App Group's queue of extension-reported "opened blocked app" events into
/// Firestore. This is intentionally decoupled from any specific `SessionViewModel`/group
/// screen: a user can open several blocked apps in strict mode and not navigate back into
/// that group's detail screen until long after the session ends (or from a completely
/// different tab), so relying on a single view's lifecycle to trigger the flush means queued
/// attempts can sit unflushed indefinitely. Call `flush()` from an app-wide scene-phase
/// observer so it fires no matter what screen the user returns to.
///
/// `flush()` is called from more than one place on the SAME scene-phase transition (the
/// app-wide observer in `MainTabView` AND `SessionViewModel.handleScenePhase`, reached via
/// `GroupDetailView`'s own observer), each as an independent, uncoordinated `Task`. Since
/// `SessionContextStore.drainPendingOpenedEvents()` reads-then-clears the queue with no
/// synchronization, two concurrent callers could both read the same events before either
/// cleared them, double-reporting the same "opened" attempt to Firestore. The `actor` below
/// makes concurrent `flush()` calls single-flight: only one drain runs at a time, and any
/// call that arrives while one is in progress awaits that SAME in-flight result instead of
/// starting its own redundant drain.
enum PendingOpenedEventFlusher {
    private actor Coordinator {
        private var inFlightTask: Task<Bool, Never>?

        func flush() async -> Bool {
            if let inFlightTask {
                return await inFlightTask.value
            }

            let task = Task { await PendingOpenedEventFlusher.performFlush() }
            inFlightTask = task
            let result = await task.value
            inFlightTask = nil
            return result
        }
    }

    private static let coordinator = Coordinator()

    @discardableResult
    static func flush() async -> Bool {
        await coordinator.flush()
    }

    private static func performFlush() async -> Bool {
        let events = SessionContextStore.shared.drainPendingOpenedEvents()
        guard !events.isEmpty else { return false }

        for event in events {
            do {
                try await SessionService.shared.markOpened(groupID: event.groupID, userUID: event.userUID)
                print("[Firestore Presence] Flushed opened event for \(event.userUID)")
            } catch {
                SessionContextStore.shared.enqueuePendingOpened(
                    for: ActiveSessionContext(
                        groupID: event.groupID,
                        sessionID: event.sessionID,
                        userUID: event.userUID
                    )
                )
                print("[Firestore Presence] Failed to flush opened event — re-queued: \(error.localizedDescription)")
            }
        }

        return true
    }
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

    // MARK: - Personal (solo) session opened-app tracking (GRO-30)

    /// Marks a solo Home-page session as active and resets the opened-attempt counter, so
    /// Shield/Monitor extensions have something to log against even without a group session.
    func startPersonalSession() {
        defaults?.set(true, forKey: StudyHallConstants.personalSessionActiveKey)
        defaults?.set(0, forKey: StudyHallConstants.personalSessionOpenedCountKey)
        defaults?.synchronize()
    }

    /// Clears the active flag and returns however many "opened blocked app" attempts were
    /// logged during the session, for use in the personal session summary.
    @discardableResult
    func endPersonalSession() -> Int {
        let count = defaults?.integer(forKey: StudyHallConstants.personalSessionOpenedCountKey) ?? 0
        defaults?.set(false, forKey: StudyHallConstants.personalSessionActiveKey)
        defaults?.set(0, forKey: StudyHallConstants.personalSessionOpenedCountKey)
        defaults?.synchronize()
        return count
    }

    func clearAll() {
        setActiveSession(nil)
        defaults?.removeObject(forKey: StudyHallConstants.pendingOpenedEventsKey)
        defaults?.removeObject(forKey: StudyHallConstants.firebaseIdTokenKey)
        defaults?.removeObject(forKey: StudyHallConstants.firebaseIdTokenExpiryKey)
        defaults?.removeObject(forKey: StudyHallConstants.lastOpenedReportKey)
        defaults?.removeObject(forKey: StudyHallConstants.lastOpenedReportAtKey)
        defaults?.set(false, forKey: StudyHallConstants.strictModeKey)
        defaults?.set(false, forKey: StudyHallConstants.personalSessionActiveKey)
        defaults?.set(0, forKey: StudyHallConstants.personalSessionOpenedCountKey)
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
