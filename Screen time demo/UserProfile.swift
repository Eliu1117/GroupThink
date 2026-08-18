//
//  UserProfile.swift
//  Screen time demo
//

import FirebaseFirestore
import Foundation

struct UserProfile: Equatable {
    let displayName: String
    /// User-chosen profile identity set via Profile Setup. Falls back to `displayName`
    /// for accounts created before this feature existed (or that skipped setup).
    let username: String
    /// Assets.xcassets imageset name for one of the 5 built-in drink avatars (e.g. "boba"),
    /// or nil if the user hasn't completed Profile Setup yet. Takes a back seat to `photoURL`
    /// when both are present (a real photo always wins over a default character avatar).
    let avatarAssetName: String?
    /// True once the user has explicitly finished (or skipped) the Profile Setup screen.
    /// Distinct from `username`/`avatarAssetName` being non-empty so RootView has an
    /// unambiguous signal to gate on, independent of how those fields default.
    let profileSetupCompleted: Bool
    let photoURL: URL?
    let focusMinutes: Int
    let totalViolations: Int
    let currentStreak: Int
    /// Last calendar day the user completed a session, stored as `"yyyy-MM-dd"`.
    let lastSessionDateStr: String?

    init?(document: DocumentSnapshot) {
        guard document.exists, let data = document.data() else { return nil }

        displayName = data["displayName"] as? String ?? "User"

        let storedUsername = (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        username = storedUsername.isEmpty ? displayName : storedUsername

        avatarAssetName = data["avatarAssetName"] as? String
        profileSetupCompleted = data["profileSetupCompleted"] as? Bool ?? false

        if let urlString = data["photoURL"] as? String, !urlString.isEmpty {
            photoURL = URL(string: urlString)
        } else {
            photoURL = nil
        }

        let stats = data["stats"] as? [String: Any]
        focusMinutes = stats?["focusMinutes"] as? Int ?? 0
        totalViolations = stats?["totalViolations"] as? Int ?? 0
        currentStreak = stats?["currentStreak"] as? Int ?? 0
        lastSessionDateStr = stats?["lastSessionDateStr"] as? String
    }
}
