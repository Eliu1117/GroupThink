//
//  StudyHallShared.swift
//  Screen time demo
//
//  Identifiers shared between the app and the DeviceActivityMonitor extension.
//  Keep this file's values in sync with the copy compiled into the monitor target.
//

import DeviceActivity
import Foundation
import ManagedSettings

enum StudyHallShared {
    /// App Group used for the shared ManagedSettingsStore and BlocklistStore defaults.
    static let appGroupID = "group.com.davechengapps.screentimedemo"
}

extension ManagedSettingsStore.Name {
    /// A named store so the app and the extension mutate the same shield.
    static let studyHall = Self("studyHall")
}

extension DeviceActivityName {
    static let studyHall = Self("studyHall")
}

extension DeviceActivityEvent.Name {
    /// Fires when the user opens a blocked app during a session.
    static let openedBlockedApp = Self("openedBlockedApp")
}
