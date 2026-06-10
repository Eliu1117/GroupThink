//
//  ExtensionAuthTokenBridge.swift
//  Screen time demo
//
//  Pre-warms and caches a Firebase ID token in the App Group so the monitor extension
//  can authenticate Firestore REST calls without spinning up the Firebase SDK.
//

import FirebaseAuth
import Foundation

enum ExtensionAuthTokenBridge {
    /// Caches the current user's ID token for the StudyHallMonitor extension.
    static func persistIDTokenForExtension(forcingRefresh: Bool = false) async {
        guard let user = Auth.auth().currentUser else {
            clearStoredToken()
            return
        }

        do {
            let token = try await user.getIDToken(forcingRefresh: forcingRefresh)
            let tokenResult = try await user.getIDTokenResult()
            guard let defaults = UserDefaults(suiteName: StudyHallConstants.appGroupID) else { return }

            defaults.set(token, forKey: StudyHallConstants.firebaseIdTokenKey)
            defaults.set(
                tokenResult.expirationDate.timeIntervalSince1970,
                forKey: StudyHallConstants.firebaseIdTokenExpiryKey
            )
            defaults.synchronize()

            print(
                "[Extension Auth] Cached ID token for extension (expires \(tokenResult.expirationDate.formatted()))"
            )
        } catch {
            print("[Extension Auth] Failed to cache ID token: \(error.localizedDescription)")
        }
    }

    static func clearStoredToken() {
        guard let defaults = UserDefaults(suiteName: StudyHallConstants.appGroupID) else { return }
        defaults.removeObject(forKey: StudyHallConstants.firebaseIdTokenKey)
        defaults.removeObject(forKey: StudyHallConstants.firebaseIdTokenExpiryKey)
        defaults.synchronize()
    }
}
