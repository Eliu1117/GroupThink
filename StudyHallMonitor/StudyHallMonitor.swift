//
//  StudyHallMonitor.swift
//  StudyHallMonitor
//
//  DeviceActivityMonitor extension — shields and unshields during scheduled intervals.
//  "Opened" detection lives in StudyHallShield (instant shield render), not threshold events.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

private enum MonitorConstants {
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    static let blocklistDefaultsKey = "studyHall.blocklistSelection"
    static let whitelistDefaultsKey = "studyHall.whitelistSelection"
    static let strictModeKey = "studyHall.strictMode"
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

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        guard event.rawValue == "openedBlockedApp" else {
            print("[DeviceActivity Monitor] Ignoring unhandled event: \(event.rawValue)")
            return
        }

        // Backup trigger: StudyHallShield handles the instant report; this catches cases
        // where the shield extension never ran. Queues fallback + attempts direct upload.
        print("[DeviceActivity Monitor] openedBlockedApp threshold — reporting opened (backup path)")
        ExtensionFirebaseWriter.markOpenedFromBackground(source: .monitor)
    }

    private func applyShields() {
        guard let defaults = UserDefaults(suiteName: MonitorConstants.appGroupID) else { return }

        let isStrict = defaults.bool(forKey: MonitorConstants.strictModeKey)

        if isStrict {
            // Strict mode: block ALL app categories, exempting only the user's whitelisted apps.
            // Reconstruct the whitelist from the shared App Group; if unavailable fall back to
            // blocking everything (safest behaviour for a study session).
            let whitelist = defaults.data(forKey: MonitorConstants.whitelistDefaultsKey)
                .flatMap { try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: $0) }
                ?? FamilyActivitySelection()

            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: whitelist.applicationTokens)
            print("[DeviceActivity Monitor] Strict mode shields re-applied (whitelist: \(whitelist.applicationTokens.count) apps)")
        } else {
            // Normal mode: block only the user's personal blocklist.
            guard
                let data = defaults.data(forKey: MonitorConstants.blocklistDefaultsKey),
                let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
            else {
                print("[DeviceActivity Monitor] No blocklist found in App Group")
                return
            }

            store.shield.applications = selection.applicationTokens
            store.shield.applicationCategories = .specific(selection.categoryTokens)
            print("[DeviceActivity Monitor] Blocklist shields re-applied")
        }
    }
}
