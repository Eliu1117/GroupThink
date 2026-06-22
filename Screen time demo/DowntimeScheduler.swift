//
//  DowntimeScheduler.swift
//  Screen time demo
//
//  Registers and tears down the DeviceActivity downtime schedule.
//  The repeating schedule fires `intervalDidStart` / `intervalDidEnd` in StudyHallMonitor
//  every 24 h, allowing the extension to apply and clear downtime shields autonomously.
//

import DeviceActivity
import Foundation

enum DowntimeScheduler {
    private static let center = DeviceActivityCenter()

    static var activityName: DeviceActivityName {
        DeviceActivityName(StudyHallConstants.downtimeActivityName)
    }

    /// Starts (or replaces) the repeating downtime schedule.
    /// Pass `nil` for `schedule` to stop monitoring.
    static func startMonitoring(schedule: DowntimeSchedule) throws {
        guard schedule.enabled else {
            stopMonitoring()
            return
        }

        stopMonitoring()

        let deviceSchedule = DeviceActivitySchedule(
            intervalStart: schedule.startComponents,
            intervalEnd: schedule.endComponents,
            repeats: true       // fires every 24 h automatically
        )

        try center.startMonitoring(activityName, during: deviceSchedule)
        print("[Downtime] Monitoring started: \(schedule.formattedStart()) – \(schedule.formattedEnd()) (repeating)")
    }

    static func stopMonitoring() {
        center.stopMonitoring([activityName])
        print("[Downtime] Monitoring stopped")
    }

    /// Temporarily lifts downtime blocking by stopping the schedule.
    /// The caller is responsible for scheduling a re-enable after the override expires.
    static func suspendForOverride() {
        stopMonitoring()
        if let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID) {
            shared.set(true, forKey: StudyHallConstants.downtimeOverrideActiveKey)
        }
        print("[Downtime] Override active — monitoring suspended")
    }

    /// Re-enables the schedule after an override expires.
    static func resumeAfterOverride(schedule: DowntimeSchedule) throws {
        if let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID) {
            shared.removeObject(forKey: StudyHallConstants.downtimeOverrideActiveKey)
        }
        try startMonitoring(schedule: schedule)
        print("[Downtime] Override ended — monitoring resumed")
    }
}
