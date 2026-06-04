//
//  BlockingManager.swift
//  Screen time demo
//
//  Applies/clears the app shield via ManagedSettings and schedules reliable
//  session timing via DeviceActivity (which keeps working if the app is killed).
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class BlockingManager {
    static let shared = BlockingManager()

    /// Named store shared with the DeviceActivityMonitor extension.
    private let store = ManagedSettingsStore(named: .studyHall)
    private let center = DeviceActivityCenter()

    private init() {}

    // MARK: - Shield

    func block(selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    func clear() {
        store.clearAllSettings()
    }

    // MARK: - Scheduled session (reliable background timing)

    /// Starts a monitored session that auto-unblocks after `durationMin`, even if the
    /// app is backgrounded or killed. The monitor extension applies/removes the shield
    /// on `intervalDidStart` / `intervalDidEnd`. Requires the extension target to exist.
    func startScheduledSession(selection: FamilyActivitySelection, durationMin: Int) throws {
        block(selection: selection)

        let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let endDate = Date().addingTimeInterval(TimeInterval(durationMin * 60))
        let end = Calendar.current.dateComponents([.hour, .minute, .second], from: endDate)

        let schedule = DeviceActivitySchedule(
            intervalStart: now,
            intervalEnd: end,
            repeats: false
        )

        // Threshold event: detect opening a blocked app early in the session.
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [
            .openedBlockedApp: DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(second: 1)
            )
        ]

        try center.startMonitoring(.studyHall, during: schedule, events: events)
    }

    func stopScheduledSession() {
        center.stopMonitoring([.studyHall])
        clear()
    }
}
