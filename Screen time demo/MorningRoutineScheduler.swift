//
//  MorningRoutineScheduler.swift  (GRO-32: enum renamed to RoutineScheduler; file name kept for Xcode compat)
//  Screen time demo
//
//  Registers the DeviceActivity routine schedule.
//
//  Time-based mode:
//    A repeating schedule from lockTime → unlockTime. `intervalDidEnd` in the
//    monitor clears shields automatically.
//
//  Activity-based mode:
//    Same schedule, but a `routineCompleted` DeviceActivityEvent monitors the
//    routine apps with a usage threshold. `eventDidReachThreshold` in the monitor
//    clears shields early once the threshold is met.
//

import DeviceActivity
import FamilyControls
import Foundation

extension DeviceActivityEvent.Name {
    static let routineCompleted = Self(StudyHallConstants.routineCompletedEventName)
}

enum RoutineScheduler {
    private static let center = DeviceActivityCenter()

    static var activityName: DeviceActivityName {
        // Raw value is "studyHall.morningRoutine" — kept for backward compat with existing
        // schedules on user devices (GRO-32).
        DeviceActivityName(StudyHallConstants.routineActivityName)
    }

    static func startMonitoring(routine: Routine, routineApps: FamilyActivitySelection) throws {
        guard routine.enabled else {
            stopMonitoring()
            return
        }

        stopMonitoring()

        let schedule = DeviceActivitySchedule(
            intervalStart: routine.lockComponents,
            intervalEnd: routine.unlockComponents,
            repeats: true
        )

        switch routine.unlockMode {
        case .timeBased:
            try center.startMonitoring(activityName, during: schedule)

        case .activityBased:
            guard !routineApps.applicationTokens.isEmpty else {
                try center.startMonitoring(activityName, during: schedule)
                return
            }

            let thresholdEvent = DeviceActivityEvent(
                applications: routineApps.applicationTokens,
                categories: routineApps.categoryTokens,
                threshold: DateComponents(minute: routine.unlockActivityMinutes)
            )

            try center.startMonitoring(
                activityName,
                during: schedule,
                events: [.routineCompleted: thresholdEvent]
            )
        }

        print("[Routine] Monitoring started: \(routine.formattedLockTime()) – \(routine.formattedUnlockTime()) (\(routine.unlockMode.label))")
    }

    static func stopMonitoring() {
        center.stopMonitoring([activityName])
        print("[Routine] Monitoring stopped")
    }
}
