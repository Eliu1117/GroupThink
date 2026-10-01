//
//  BackgroundURLSessionRelauncher.swift
//  Screen time demo
//
//  Reconnects to extension background URLSessions when iOS wakes the main app
//  to deliver nsurlsessiond completion events.
//

import Foundation

enum BackgroundURLSessionRelauncher {
    /// Recreates the background session so delegate callbacks drain after extension upload.
    static func handleEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard StudyHallConstants.backgroundURLSessionIdentifiers.contains(identifier) else {
            completionHandler()
            return
        }

        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sharedContainerIdentifier = StudyHallConstants.appGroupID

        let delegate = MainAppBackgroundURLSessionDelegate.shared
        delegate.storeCompletionHandler(completionHandler)

        _ = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        print("[Extension REST] Main app reconnected to background URL session — \(identifier)")
    }
}

private final class MainAppBackgroundURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = MainAppBackgroundURLSessionDelegate()

    private var completionHandler: (() -> Void)?

    private override init() {
        super.init()
    }

    func storeCompletionHandler(_ handler: @escaping () -> Void) {
        completionHandler = handler
    }

    // Parameter type must be `URLSession` (not `String`) to actually match
    // `URLSessionDelegate`'s optional requirement — a mismatched type here means this method
    // is never invoked by the system at all, silently dropping the completion handler and
    // the background session would never be told its events were drained.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier ?? "unknown"
        print("[Extension REST] Main app drained background session — \(identifier)")
        let handler = completionHandler
        completionHandler = nil
        handler?()
    }

    @objc func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[Extension REST] Main app observed background upload error: \(error.localizedDescription)")
            return
        }

        if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
            print("[Extension REST] Main app observed background upload HTTP \(http.statusCode)")
        }
    }
}
