//
//  ExtensionSessionContext.swift
//  ExtensionSupport
//
//  Reads active session metadata from the shared App Group container.
//

import Foundation

struct ExtensionSessionContext: Equatable {
    let groupID: String
    let sessionID: String
    let userUID: String

    private enum Keys {
        static let appGroupID = "group.com.davechengapps.screentimedemo"
        static let activeSessionContextKey = "studyHall.activeSessionContext"
        static let currentGroupIdKey = "currentGroupId"
        static let currentSessionIdKey = "currentSessionId"
        static let currentUserIdKey = "currentUserId"
    }

    private struct EncodedContext: Codable {
        let groupID: String
        let sessionID: String
        let userUID: String
    }

    static func load() -> ExtensionSessionContext? {
        guard let defaults = UserDefaults(suiteName: Keys.appGroupID) else { return nil }

        if let data = defaults.data(forKey: Keys.activeSessionContextKey),
           let encoded = try? JSONDecoder().decode(EncodedContext.self, from: data) {
            return ExtensionSessionContext(
                groupID: encoded.groupID,
                sessionID: encoded.sessionID,
                userUID: encoded.userUID
            )
        }

        guard
            let groupID = defaults.string(forKey: Keys.currentGroupIdKey),
            let sessionID = defaults.string(forKey: Keys.currentSessionIdKey),
            let userUID = defaults.string(forKey: Keys.currentUserIdKey)
        else {
            return nil
        }

        return ExtensionSessionContext(groupID: groupID, sessionID: sessionID, userUID: userUID)
    }
}
