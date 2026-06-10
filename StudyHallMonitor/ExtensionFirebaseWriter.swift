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
    /// Blocks the extension thread until the write completes or times out so iOS does not suspend the process mid-flight.
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

        let semaphore = DispatchSemaphore(value: 0)
        var writeError: Error?

        document.updateData([
            "participants.\(context.userUID).state": "opened",
        ]) { error in
            writeError = error
            if let error {
                print("[Extension Firebase] ERROR: Background update failed: \(error.localizedDescription)")
            } else {
                print("[Extension Firebase] SUCCESS: Background status set to opened for \(context.userUID)")
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 5.0)
        if waitResult == .timedOut {
            print("[Extension Firebase] Firestore write timed out after 5s — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
        } else if writeError != nil {
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
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
