//
//  StudyHallMonitor.swift
//  StudyHallMonitor
//
//  DeviceActivityMonitor extension — shields and unshields during scheduled intervals.
//  Handles both the focus-session activity ("studyHall") and the nightly downtime activity
//  ("studyHall.downtime") using separate named ManagedSettingsStores so they don't conflict.
//
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
    // GRO-12: downtime keys
    static let downtimeActivityName = "studyHall.downtime"
    static let downtimeAllowedAppsKey = "studyHall.downtimeAllowedApps"
    static let downtimeOverrideActiveKey = "studyHall.downtimeOverrideActive"
    static let downtimeStoreName = "com.davechengapps.screentimedemo.downtime"
    // GRO-13 / GRO-32: routine keys (raw values kept as "morningRoutine" for backward compat)
    static let routineActivityName = "studyHall.morningRoutine"
    static let routineCompletedEventName = "routineCompleted"
    static let routineAppsKey = "studyHall.routineApps"
    static let routineUnlockModeKey = "studyHall.routineUnlockMode"
    static let routineStoreName = "com.davechengapps.screentimedemo.morningRoutine"
}

class StudyHallMonitor: DeviceActivityMonitor {
    /// Default store used for focus-session shields.
    private let sessionStore = ManagedSettingsStore()
    /// Separate named store for downtime shields so they can be cleared independently.
    private let downtimeStore = ManagedSettingsStore(named: ManagedSettingsStore.Name(MonitorConstants.downtimeStoreName))
    /// Separate named store for routine shields.
    private let routineStore = ManagedSettingsStore(named: ManagedSettingsStore.Name(MonitorConstants.routineStoreName))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        switch activity.rawValue {
        case MonitorConstants.downtimeActivityName:
            applyDowntimeShields()
        case MonitorConstants.routineActivityName:
            applyRoutineShields()
        default:
            applySessionShields()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        switch activity.rawValue {
        case MonitorConstants.downtimeActivityName:
            downtimeStore.clearAllSettings()
            print("[DeviceActivity Monitor] Downtime ended — shields cleared")
        case MonitorConstants.routineActivityName:
            routineStore.clearAllSettings()
            print("[DeviceActivity Monitor] Routine ended — shields cleared")
        default:
            sessionStore.clearAllSettings()
            print("[DeviceActivity Monitor] Session ended — shields cleared")
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        switch event.rawValue {
        case MonitorConstants.routineCompletedEventName:
            // GRO-13 activity-based unlock: user spent enough time in routine apps.
            routineStore.clearAllSettings()
            print("[DeviceActivity Monitor] Routine completed — morning shields lifted early")

        case "openedBlockedApp":
            // Backup trigger: StudyHallShield handles the instant report; this catches cases
            // where the shield extension never ran. Queues fallback + attempts direct upload.
            print("[DeviceActivity Monitor] openedBlockedApp threshold — reporting opened (backup path)")
            ExtensionFirebaseWriter.markOpenedFromBackground(source: .monitor)

        default:
            print("[DeviceActivity Monitor] Ignoring unhandled event: \(event.rawValue)")
        }
    }

    // MARK: - Session shields

    private func applySessionShields() {
        guard let defaults = UserDefaults(suiteName: MonitorConstants.appGroupID) else { return }

        let isStrict = defaults.bool(forKey: MonitorConstants.strictModeKey)

        if isStrict {
            // Strict mode: block ALL app categories, exempting only the user's whitelisted apps.
            let whitelist = defaults.data(forKey: MonitorConstants.whitelistDefaultsKey)
                .flatMap { try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: $0) }
                ?? FamilyActivitySelection()

            sessionStore.shield.applications = nil
            sessionStore.shield.applicationCategories = .all(except: whitelist.applicationTokens)
            print("[DeviceActivity Monitor] Strict mode shields re-applied (whitelist: \(whitelist.applicationTokens.count) apps)")
        } else {
            guard
                let data = defaults.data(forKey: MonitorConstants.blocklistDefaultsKey),
                let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
            else {
                print("[DeviceActivity Monitor] No blocklist found in App Group")
                return
            }

            sessionStore.shield.applications = selection.applicationTokens
            sessionStore.shield.applicationCategories = .specific(selection.categoryTokens)
            print("[DeviceActivity Monitor] Blocklist shields re-applied")
        }
    }

    // MARK: - Morning routine shields (GRO-13)

    private func applyRoutineShields() {
        guard let defaults = UserDefaults(suiteName: MonitorConstants.appGroupID) else { return }

        // Allowed routine apps stay unblocked so the user can earn their unlock.
        let routineApps = defaults.data(forKey: MonitorConstants.routineAppsKey)
            .flatMap { try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()

        routineStore.shield.applications = nil
        routineStore.shield.applicationCategories = .all(except: routineApps.applicationTokens)
        print("[DeviceActivity Monitor] Morning routine shields applied (routine apps: \(routineApps.applicationTokens.count))")
    }

    // MARK: - Downtime shields (GRO-12)

    private func applyDowntimeShields() {
        guard let defaults = UserDefaults(suiteName: MonitorConstants.appGroupID) else { return }

        // If the user has an active peer-approved override, skip shielding.
        if defaults.bool(forKey: MonitorConstants.downtimeOverrideActiveKey) {
            print("[DeviceActivity Monitor] Downtime override active — skipping shields")
            return
        }

        let allowed = defaults.data(forKey: MonitorConstants.downtimeAllowedAppsKey)
            .flatMap { try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: $0) }
            ?? FamilyActivitySelection()

        // Block everything except the user's downtime allowed-apps list.
        downtimeStore.shield.applications = nil
        downtimeStore.shield.applicationCategories = .all(except: allowed.applicationTokens)
        print("[DeviceActivity Monitor] Downtime shields applied (allowed: \(allowed.applicationTokens.count) apps)")
    }
}
