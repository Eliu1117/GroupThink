//
//  ExtensionFirebaseWriter.swift
//  StudyHallMonitor
//
//  Initializes Firebase inside the extension and writes opened presence directly to Firestore.
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

private enum ExtensionKeys {
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    static let currentGroupIdKey = "currentGroupId"
    static let currentSessionIdKey = "currentSessionId"
    static let currentUserIdKey = "currentUserId"
}

enum ExtensionFirebaseWriter {
    private static let configureLock = NSLock()
    private static var isConfigured = false

    /// Marks the current user as `opened` on the active session document.
    static func markOpenedFromBackground() {
        guard let context = loadSessionContext() else {
            print("[Extension Firebase] Missing session context — cannot write opened state")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        configureFirebaseIfNeeded()

        guard Auth.auth().currentUser != nil else {
            print("[Extension Firebase] No authenticated user in extension — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        let document = Firestore.firestore()
            .collection("groups").document(context.groupID)
            .collection("sessions").document(context.sessionID)

        document.updateData([
            "participants.\(context.userUID).state": "opened",
        ]) { error in
            if let error {
                print("[Extension Firebase] Firestore write failed — queueing fallback: \(error.localizedDescription)")
                ExtensionSessionBridge.enqueuePendingOpenedFallback()
            } else {
                print("[Extension Firebase] Wrote opened state for \(context.userUID) on session \(context.sessionID)")
            }
        }
    }

    // MARK: - Firebase bootstrap

    private static func configureFirebaseIfNeeded() {
        configureLock.lock()
        defer { configureLock.unlock() }

        guard !isConfigured else { return }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        do {
            let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String ?? ""
            try Auth.auth().useUserAccessGroup("\(prefix)\(ExtensionKeys.appGroupID)")
        } catch {
            print("[Extension Firebase] Auth keychain group setup failed: \(error.localizedDescription)")
        }

        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings

        isConfigured = true
        print("[Extension Firebase] Firebase configured in extension")
    }

    private static func loadSessionContext() -> (groupID: String, sessionID: String, userUID: String)? {
        guard let defaults = UserDefaults(suiteName: ExtensionKeys.appGroupID) else { return nil }

        guard
            let groupID = defaults.string(forKey: ExtensionKeys.currentGroupIdKey),
            let sessionID = defaults.string(forKey: ExtensionKeys.currentSessionIdKey),
            let userUID = defaults.string(forKey: ExtensionKeys.currentUserIdKey)
        else {
            return nil
        }

        return (groupID, sessionID, userUID)
    }
}
