//
//  ExtensionFirebaseWriter.swift
//  StudyHallMonitor
//
//  Plan A: synchronous Firestore REST PATCH — no Firestore SDK handshake in the extension.
//
//  Plan B fallback (not compiled): if security rules block REST or tokens cannot be cached,
//  re-link FirebaseFirestore in the extension target and call `ExtensionFirestoreSDKFallback`
//  after warming the client with `Firestore.firestore().disableNetwork()` / `enableNetwork()`
//  plus `waitForPendingWrites()` before `updateData`, blocking with a DispatchSemaphore.
//

import Foundation

enum ExtensionFirebaseWriter {
    private enum Keys {
        static let appGroupID = "group.com.davechengapps.screentimedemo"
        static let firebaseIdTokenKey = "studyHall.firebaseIdToken"
        static let firebaseIdTokenExpiryKey = "studyHall.firebaseIdTokenExpiry"
        static let projectIDPlistKey = "PROJECT_ID"
    }

    private static let requestTimeout: TimeInterval = 5.0
    private static let tokenExpiryBuffer: TimeInterval = 60

    /// Marks the current user as `opened` via Firestore REST. Blocks until HTTP completes or times out.
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

        let success = patchOpenedState(
            projectID: projectID,
            context: context,
            idToken: idToken
        )

        if success {
            print("[Extension REST] SUCCESS: Background status set to opened for \(context.userUID)")
        } else {
            print("[Extension REST] Background update failed — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
        }
    }

    // MARK: - Firestore REST

    private static func patchOpenedState(
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

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error {
                print("[Extension REST] ERROR: \(error.localizedDescription)")
                return
            }

            guard let http = response as? HTTPURLResponse else {
                print("[Extension REST] ERROR: Missing HTTP response")
                return
            }

            if http.statusCode == 200 {
                succeeded = true
                return
            }

            let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[Extension REST] ERROR: HTTP \(http.statusCode) — \(responseBody)")
        }

        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + requestTimeout)
        if waitResult == .timedOut {
            print("[Extension REST] ERROR: Request timed out after \(requestTimeout)s")
            task.cancel()
            return false
        }

        return succeeded
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
