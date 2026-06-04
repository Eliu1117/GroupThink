//
//  AppUser.swift
//  Screen time demo
//
//  Firestore document model for `users/{uid}`.
//

import FirebaseFirestore
import Foundation

struct AppUser: Codable, Identifiable {
    @DocumentID var id: String?
    var displayName: String
    var photoURL: String?
    var fcmTokens: [String]
    var stats: Stats

    struct Stats: Codable {
        var focusMinutes: Int
        var currentStreak: Int
        /// Day of the last completed session, used to compute streaks.
        var lastSessionDay: String?

        init(focusMinutes: Int = 0, currentStreak: Int = 0, lastSessionDay: String? = nil) {
            self.focusMinutes = focusMinutes
            self.currentStreak = currentStreak
            self.lastSessionDay = lastSessionDay
        }
    }

    init(
        id: String? = nil,
        displayName: String,
        photoURL: String? = nil,
        fcmTokens: [String] = [],
        stats: Stats = Stats()
    ) {
        self.id = id
        self.displayName = displayName
        self.photoURL = photoURL
        self.fcmTokens = fcmTokens
        self.stats = stats
    }
}
