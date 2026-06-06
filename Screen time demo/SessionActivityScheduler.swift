//
//  SessionActivityScheduler.swift
//  Screen time demo
//
//  Schedules DeviceActivity intervals for reliable background unblock.
//

import DeviceActivity
import Foundation

enum SessionActivityScheduler {
    private static let center = DeviceActivityCenter()

    static var activityName: DeviceActivityName {
        DeviceActivityName(StudyHallConstants.studyHallActivityName)
    }

    static func startMonitoring(until endDate: Date) throws {
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

        try center.startMonitoring(activityName, during: schedule)
        print("[DeviceActivity] Scheduled monitoring until \(endDate.formatted())")
    }

    static func stopMonitoring() {
        center.stopMonitoring([activityName])
        print("[DeviceActivity] Stopped monitoring")
    }
}
