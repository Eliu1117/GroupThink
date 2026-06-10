//
//  FirebaseAuthConfigurator.swift
//  Screen time demo
//
//  Shares Firebase Auth keychain state between the main app and StudyHallMonitor extension.
//

import FirebaseAuth
import FirebaseCore
import Foundation

enum FirebaseAuthConfigurator {
    /// Configures Firebase Auth to use the App Group keychain so the extension can reuse the signed-in user.
    static func configureSharedKeychainAccess() {
        guard FirebaseApp.app() != nil else { return }

        do {
            try Auth.auth().useUserAccessGroup(sharedKeychainAccessGroup())
            print("[Firebase Auth] Shared keychain access group configured")
        } catch {
            print("[Firebase Auth] Shared keychain setup failed: \(error.localizedDescription)")
        }
    }

    static func sharedKeychainAccessGroup() -> String {
        let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String ?? ""
        return "\(prefix)\(StudyHallConstants.appGroupID)"
    }
}
