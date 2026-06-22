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
        static let lastOpenedReportAtKey = "studyHall.lastOpenedReportAt"
        static let projectIDPlistKey = "PROJECT_ID"
    }

    private static let tokenExpiryBuffer: TimeInterval = 60
    private static let directUploadDedupeWindow: TimeInterval = 30
    private static let sessionDelegate = BackgroundURLSessionDelegate.shared
    private static var backgroundSessions: [String: URLSession] = [:]
    private static let sessionLock = NSLock()

    /// Enqueues a background Firestore REST PATCH. Returns immediately; nsurlsessiond performs the upload.
    static func markOpenedFromBackground(
        source: OpenedWriteSource,
        context: ExtensionSessionContext? = ExtensionSessionContext.load()
    ) {
        // Always attempt to queue the App Group fallback first — before any guard that could
        // bail out early.  enqueuePendingOpenedFallback loads its own context, so it handles
        // the nil case internally and is safe to call unconditionally.
        ExtensionSessionBridge.enqueuePendingOpenedFallback()

        guard let context else {
            print("[\(source.logLabel)] Missing session context — direct upload skipped; fallback queued if context was available")
            return
        }

        guard shouldAttemptDirectUpload(context: context) else {
            print("[\(source.logLabel)] Direct upload recently attempted for \(context.userUID) — fallback queued")
            return
        }

        guard let projectID = loadProjectID() else {
            print("[\(source.logLabel)] Missing Firebase project ID — relying on queued fallback")
            return
        }

        guard let idToken = loadCachedIDToken() else {
            print("[\(source.logLabel)] No valid cached ID token — relying on queued fallback")
            return
        }

        if enqueueBackgroundPatch(source: source, projectID: projectID, context: context, idToken: idToken) {
            markDirectUploadAttempted(context: context)
        } else {
            print("[\(source.logLabel)] Failed to enqueue background upload — relying on queued fallback")
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
                "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents/groups/\(context.groupID)/sessions/current?updateMask.fieldPaths=\(encodedMask)"
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

    /// Dedupes rapid repeated shield renders, but only suppresses uploads that were actually
    /// enqueued recently — a failed attempt never blocks the next one.
    private static func shouldAttemptDirectUpload(context: ExtensionSessionContext) -> Bool {
        guard let defaults = UserDefaults(suiteName: Keys.appGroupID) else { return true }

        guard defaults.string(forKey: Keys.lastOpenedReportKey) == marker(for: context) else {
            return true
        }

        let lastAttempt = defaults.double(forKey: Keys.lastOpenedReportAtKey)
        return Date().timeIntervalSince1970 - lastAttempt > directUploadDedupeWindow
    }

    private static func markDirectUploadAttempted(context: ExtensionSessionContext) {
        guard let defaults = UserDefaults(suiteName: Keys.appGroupID) else { return }
        defaults.set(marker(for: context), forKey: Keys.lastOpenedReportKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastOpenedReportAtKey)
        defaults.synchronize()
    }

    private static func marker(for context: ExtensionSessionContext) -> String {
        "\(context.sessionID):\(context.userUID)"
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
