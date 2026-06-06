//
//  StudyHallMonitor.swift
//  StudyHallMonitor
//
//  DeviceActivityMonitor extension — applies/clears shields when the app is not running.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

private enum MonitorConstants {
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    static let blocklistDefaultsKey = "studyHall.blocklistSelection"
}

class StudyHallMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        applyShields()
        print("[DeviceActivity Monitor] intervalDidStart — shields applied")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        store.clearAllSettings()
        print("[DeviceActivity Monitor] intervalDidEnd — shields cleared")
    }

    private func applyShields() {
        guard
            let defaults = UserDefaults(suiteName: MonitorConstants.appGroupID),
            let data = defaults.data(forKey: MonitorConstants.blocklistDefaultsKey),
            let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            print("[DeviceActivity Monitor] No blocklist found in App Group")
            return
        }

        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = .specific(selection.categoryTokens)
    }
}
