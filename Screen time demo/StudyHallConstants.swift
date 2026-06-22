//
//  StudyHallConstants.swift
//  Screen time demo
//
//  Shared constants for app ↔ extension communication via App Group.
//

import Foundation

enum StudyHallConstants {
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    static let blocklistDefaultsKey = "studyHall.blocklistSelection"
    /// Apps the user keeps available during strict-mode sessions.
    static let whitelistDefaultsKey = "studyHall.whitelistSelection"
    static let studyHallActivityName = "studyHall"
    static let openedBlockedAppEventName = "openedBlockedApp"

    // App Group keys shared with StudyHallMonitor extension (must stay in sync).
    static let activeSessionContextKey = "studyHall.activeSessionContext"
    static let pendingOpenedEventsKey = "studyHall.pendingOpenedEvents"

    /// Flat keys read directly by the extension before a background Firestore write.
    static let currentGroupIdKey = "currentGroupId"
    static let currentSessionIdKey = "currentSessionId"
    static let currentUserIdKey = "currentUserId"

    /// Firebase Auth ID token cached by the main app for extension REST writes.
    static let firebaseIdTokenKey = "studyHall.firebaseIdToken"
    static let firebaseIdTokenExpiryKey = "studyHall.firebaseIdTokenExpiry"

    /// Background URLSession identifiers shared with extensions (must stay in sync).
    static let backgroundURLSessionIdentifier = "com.davechengapps.screentimedemo.backgroundsession"
    static let shieldBackgroundURLSessionIdentifier = "com.davechengapps.screentimedemo.shieldTask"

    /// Dedupes repeated shield-configuration callbacks for the same session participant.
    static let lastOpenedReportKey = "studyHall.lastOpenedReport"
    static let lastOpenedReportAtKey = "studyHall.lastOpenedReportAt"

    /// Whether the current session is running in strict mode.
    /// Read by StudyHallMonitor to apply the right shield policy when intervalDidStart fires.
    static let strictModeKey = "studyHall.strictMode"

    static let backgroundURLSessionIdentifiers = [
        backgroundURLSessionIdentifier,
        shieldBackgroundURLSessionIdentifier,
    ]

    // GRO-11: user preference — defaults to true; opt-out stored in standard UserDefaults.
    static let breakVoteNotificationsEnabledKey = "studyHall.breakVoteNotificationsEnabled"

    // GRO-12: Downtime enforcement
    /// DeviceActivity name for the nightly downtime schedule.
    static let downtimeActivityName = "studyHall.downtime"
    /// App Group key: encoded FamilyActivitySelection allowed during downtime.
    static let downtimeAllowedAppsKey = "studyHall.downtimeAllowedApps"
    /// App Group key: Bool — whether the user is currently inside an approved downtime override.
    static let downtimeOverrideActiveKey = "studyHall.downtimeOverrideActive"
    /// Named ManagedSettingsStore used exclusively for downtime shields.
    static let downtimeStoreName = "com.davechengapps.screentimedemo.downtime"

    // GRO-13 / GRO-32: Routine (formerly "Morning Routine")
    // Raw string values are intentionally kept as "morningRoutine" / "studyHall.morningRoutine"
    // to preserve backward-compat with existing DeviceActivitySchedule registrations and
    // the named ManagedSettingsStore declared in entitlements.
    /// DeviceActivity name for the routine schedule.
    static let routineActivityName = "studyHall.morningRoutine"
    /// DeviceActivity event name: fired when the user accumulates enough time in routine apps.
    static let routineCompletedEventName = "routineCompleted"
    /// App Group key: encoded FamilyActivitySelection for approved routine apps.
    static let routineAppsKey = "studyHall.routineApps"
    /// App Group key: RoutineUnlockMode raw value.
    static let routineUnlockModeKey = "studyHall.routineUnlockMode"
    /// App Group key: minutes needed for activity-based unlock.
    static let routineUnlockMinutesKey = "studyHall.routineUnlockMinutes"
    /// Named ManagedSettingsStore used exclusively for routine shields.
    /// Value kept as "morningRoutine" — changing it requires entitlement + App Group updates.
    static let routineStoreName = "com.davechengapps.screentimedemo.morningRoutine"
}
