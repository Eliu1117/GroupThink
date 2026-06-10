//
//  BackgroundURLSessionRelauncher.swift
//  Screen time demo
//
//  Reconnects to the extension's background URLSession when iOS wakes the main app
//  to deliver nsurlsessiond completion events.
//

import Foundation

enum BackgroundURLSessionRelauncher {
    /// Must match the identifier used by StudyHallMonitor's background URLSession.
    static let identifier = "com.davechengapps.screentimedemo.backgroundsession"

    /// Recreates the background session so delegate callbacks drain after extension upload.
    static func handleEvents(completionHandler: @escaping () -> Void) {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sharedContainerIdentifier = StudyHallConstants.appGroupID

        let delegate = MainAppBackgroundURLSessionDelegate.shared
        delegate.storeCompletionHandler(completionHandler)

        // Retain the reconnected session for the lifetime of the delegate callbacks.
        _ = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        print("[Extension REST] Main app reconnected to background URL session")
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

    @objc func urlSessionDidFinishEvents(forBackgroundURLSession sessionIdentifier: String) {
        print("[Extension REST] Main app drained background session — \(sessionIdentifier)")
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
