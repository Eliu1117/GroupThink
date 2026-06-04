//
//  StudyHallMonitor.swift
//  StudyHallMonitor (DeviceActivityMonitor extension)
//
//  Runs out-of-process so session timing/blocking survives the app being killed.
//  This file belongs to a SEPARATE extension target — see SETUP.md for how to add it.
//  It is intentionally self-contained (no Firebase, no app imports).
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

private enum Shared {
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    static let selectionKey = "blocklist.selection"
    static let openedFlagKey = "presence.openedBlockedApp"
    static let openedAtKey = "presence.openedAt"
    static let storeName = ManagedSettingsStore.Name("studyHall")
    static let openedEvent = DeviceActivityEvent.Name("openedBlockedApp")
}

final class StudyHallMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: Shared.storeName)
    private let defaults = UserDefaults(suiteName: Shared.appGroupID)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        applyShieldFromSavedSelection()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        store.clearAllSettings()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard event == Shared.openedEvent else { return }
        // The extension can't talk to Firebase; flag it for the app to report next launch.
        defaults?.set(true, forKey: Shared.openedFlagKey)
        defaults?.set(Date(), forKey: Shared.openedAtKey)
    }

    private func applyShieldFromSavedSelection() {
        guard
            let data = defaults?.data(forKey: Shared.selectionKey),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
}
