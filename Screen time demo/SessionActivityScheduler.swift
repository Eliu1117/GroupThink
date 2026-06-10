//
//  SessionActivityScheduler.swift
//  Screen time demo
//
//  Schedules DeviceActivity intervals for reliable background unshield at session end.
//  Opened-app detection: StudyHallShield (instant, on shield render) with the monitor's
//  threshold event as a backup queue trigger.
//

import DeviceActivity
import FamilyControls
import Foundation

extension DeviceActivityEvent.Name {
    static let openedBlockedApp = Self(StudyHallConstants.openedBlockedAppEventName)
}

enum SessionActivityScheduler {
    private static let center = DeviceActivityCenter()

    static var activityName: DeviceActivityName {
        DeviceActivityName(StudyHallConstants.studyHallActivityName)
    }

    static func startMonitoring(
        until endDate: Date,
        selection: FamilyActivitySelection
    ) throws {
        stopMonitoring()

        let now = Date()
        guard endDate > now else {
            print("[DeviceActivity] End date is in the past — skipping schedule")
            return
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now
        )
        let endComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: endDate
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
            events[.openedBlockedApp] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                threshold: DateComponents(second: 1)
            )
        }

        if events.isEmpty {
            try center.startMonitoring(activityName, during: schedule)
        } else {
            try center.startMonitoring(activityName, during: schedule, events: events)
        }

        print("[DeviceActivity] Scheduled monitoring until \(endDate.formatted()) with \(events.count) event(s)")
    }

    static func stopMonitoring() {
        center.stopMonitoring([activityName])
        print("[DeviceActivity] Stopped monitoring")
    }
}
