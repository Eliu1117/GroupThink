//
//  UserProfile.swift
//  Screen time demo
//

import FirebaseFirestore
import Foundation

struct UserProfile: Equatable {
    let displayName: String
    let photoURL: URL?
    let focusMinutes: Int
    let currentStreak: Int

    init?(document: DocumentSnapshot) {
        guard document.exists, let data = document.data() else { return nil }

        displayName = data["displayName"] as? String ?? "User"

        if let urlString = data["photoURL"] as? String, !urlString.isEmpty {
            photoURL = URL(string: urlString)
        } else {
            photoURL = nil
        }

        let stats = data["stats"] as? [String: Any]
        focusMinutes = stats?["focusMinutes"] as? Int ?? 0
        currentStreak = stats?["currentStreak"] as? Int ?? 0
    }
}
