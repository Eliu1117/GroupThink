//
//  ExtensionFirebaseWriter.swift
//  StudyHallMonitor
//
//  Firestore REST PATCH via URLSessionConfiguration.background — handed off to nsurlsessiond
//  so network continues after the DeviceActivityMonitor extension is suspended.
//

import Foundation

enum ExtensionFirebaseWriter {
    private enum Keys {
        static let appGroupID = "group.com.davechengapps.screentimedemo"
        static let backgroundSessionIdentifier = "com.davechengapps.screentimedemo.backgroundsession"
        static let firebaseIdTokenKey = "studyHall.firebaseIdToken"
        static let firebaseIdTokenExpiryKey = "studyHall.firebaseIdTokenExpiry"
        static let projectIDPlistKey = "PROJECT_ID"
    }

    private static let tokenExpiryBuffer: TimeInterval = 60
    private static let sessionDelegate = BackgroundURLSessionDelegate.shared

    private static let backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Keys.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.sharedContainerIdentifier = Keys.appGroupID
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    /// Enqueues a background Firestore REST PATCH. Returns immediately; nsurlsessiond performs the upload.
    static func markOpenedFromBackground(context: ExtensionSessionContext? = ExtensionSessionContext.load()) {
        guard let context else {
            print("[Extension REST] Missing session context — cannot write opened state")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        guard let projectID = loadProjectID() else {
            print("[Extension REST] Missing Firebase project ID — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        guard let idToken = loadCachedIDToken() else {
            print("[Extension REST] No valid cached ID token — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        guard enqueueBackgroundPatch(projectID: projectID, context: context, idToken: idToken) else {
            print("[Extension REST] Failed to enqueue background upload — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }
    }

    // MARK: - Background Firestore REST

    @discardableResult
    private static func enqueueBackgroundPatch(
        projectID: String,
        context: ExtensionSessionContext,
        idToken: String
    ) -> Bool {
        let fieldPath = "participants.\(context.userUID).state"
        guard
            let encodedMask = fieldPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let body = buildPatchBody(userUID: context.userUID),
            let url = URL(string:
                "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/groups/\(context.groupID)/sessions/\(context.sessionID)?updateMask.fieldPaths=\(encodedMask)"
            )
        else {
            print("[Extension REST] Failed to build PATCH request")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = backgroundSession.uploadTask(with: request, from: body)
        task.resume()

        print(
            "[Extension REST] Enqueued background upload for \(context.userUID) on session \(context.sessionID)"
        )
        return true
    }

    private static func buildPatchBody(userUID: String) -> Data? {
        let body: [String: Any] = [
            "fields": [
                "participants": [
                    "mapValue": [
                        "fields": [
                            userUID: [
                                "mapValue": [
                                    "fields": [
                                        "state": ["stringValue": "opened"],
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - App Group / plist reads

    private static func loadCachedIDToken() -> String? {
        guard
            let defaults = UserDefaults(suiteName: Keys.appGroupID),
            let token = defaults.string(forKey: Keys.firebaseIdTokenKey),
            !token.isEmpty
        else {
            return nil
        }

        let expiry = defaults.double(forKey: Keys.firebaseIdTokenExpiryKey)
        if expiry > 0 {
            let secondsRemaining = expiry - Date().timeIntervalSince1970
            if secondsRemaining <= tokenExpiryBuffer {
                print("[Extension REST] Cached ID token expired or near expiry (\(Int(secondsRemaining))s left)")
                return nil
            }
        }

        return token
    }

    private static func loadProjectID() -> String? {
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let plist = NSDictionary(contentsOfFile: path),
            let projectID = plist[Keys.projectIDPlistKey] as? String
        else {
            return nil
        }

        return projectID
    }
}
