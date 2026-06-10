//
//  ExtensionFirebaseWriter.swift
//  ExtensionSupport
//
//  Firestore REST PATCH via URLSessionConfiguration.background — handed off to nsurlsessiond.
//

import Foundation

enum OpenedWriteSource {
    case shield
    case monitor

    var backgroundSessionIdentifier: String {
        switch self {
        case .shield:
            return "com.davechengapps.screentimedemo.shieldTask"
        case .monitor:
            return "com.davechengapps.screentimedemo.backgroundsession"
        }
    }

    var logLabel: String {
        switch self {
        case .shield:
            return "Shield REST"
        case .monitor:
            return "Extension REST"
        }
    }
}

enum ExtensionFirebaseWriter {
    private enum Keys {
        static let appGroupID = "group.com.davechengapps.screentimedemo"
        static let firebaseIdTokenKey = "studyHall.firebaseIdToken"
        static let firebaseIdTokenExpiryKey = "studyHall.firebaseIdTokenExpiry"
        static let lastOpenedReportKey = "studyHall.lastOpenedReport"
        static let projectIDPlistKey = "PROJECT_ID"
    }

    private static let tokenExpiryBuffer: TimeInterval = 60
    private static let sessionDelegate = BackgroundURLSessionDelegate.shared
    private static var backgroundSessions: [String: URLSession] = [:]
    private static let sessionLock = NSLock()

    /// Enqueues a background Firestore REST PATCH. Returns immediately; nsurlsessiond performs the upload.
    static func markOpenedFromBackground(
        source: OpenedWriteSource,
        context: ExtensionSessionContext? = ExtensionSessionContext.load()
    ) {
        guard let context else {
            print("[\(source.logLabel)] Missing session context — cannot write opened state")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        guard shouldReportOpened(context: context) else {
            print("[\(source.logLabel)] Skipping duplicate opened report for \(context.userUID)")
            return
        }

        guard let projectID = loadProjectID() else {
            print("[\(source.logLabel)] Missing Firebase project ID — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        guard let idToken = loadCachedIDToken() else {
            print("[\(source.logLabel)] No valid cached ID token — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        guard enqueueBackgroundPatch(
            source: source,
            projectID: projectID,
            context: context,
            idToken: idToken
        ) else {
            print("[\(source.logLabel)] Failed to enqueue background upload — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }
    }

    // MARK: - Background Firestore REST

    @discardableResult
    private static func enqueueBackgroundPatch(
        source: OpenedWriteSource,
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
            print("[\(source.logLabel)] Failed to build PATCH request")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let session = backgroundSession(for: source)
        let task = session.uploadTask(with: request, from: body)
        task.resume()

        print(
            "[\(source.logLabel)] Enqueued background upload for \(context.userUID) on session \(context.sessionID)"
        )
        return true
    }

    private static func backgroundSession(for source: OpenedWriteSource) -> URLSession {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        let identifier = source.backgroundSessionIdentifier
        if let existing = backgroundSessions[identifier] {
            return existing
        }

        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.sharedContainerIdentifier = Keys.appGroupID

        let session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        backgroundSessions[identifier] = session
        return session
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

    private static func shouldReportOpened(context: ExtensionSessionContext) -> Bool {
        guard let defaults = UserDefaults(suiteName: Keys.appGroupID) else { return true }

        let marker = "\(context.sessionID):\(context.userUID)"
        if defaults.string(forKey: Keys.lastOpenedReportKey) == marker {
            return false
        }

        defaults.set(marker, forKey: Keys.lastOpenedReportKey)
        defaults.synchronize()
        return true
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
