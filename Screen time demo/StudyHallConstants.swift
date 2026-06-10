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
}
