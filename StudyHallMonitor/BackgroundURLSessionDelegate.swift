//
//  BackgroundURLSessionDelegate.swift
//  StudyHallMonitor
//
//  Receives completion callbacks for background URLSession uploads handed off to nsurlsessiond.
//

import Foundation

final class BackgroundURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = BackgroundURLSessionDelegate()

    private var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
    }

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
    }

    @objc func urlSessionDidFinishEvents(forBackgroundURLSession sessionIdentifier: String) {
        print("[Extension REST] Background session finished events — \(sessionIdentifier)")
        let handler = backgroundCompletionHandler
        backgroundCompletionHandler = nil
        handler?()
    }

    @objc func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[Extension REST] Background upload failed: \(error.localizedDescription)")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        guard let http = task.response as? HTTPURLResponse else {
            print("[Extension REST] Background upload missing HTTP response — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
            return
        }

        if http.statusCode == 200 {
            print("[Extension REST] SUCCESS: Background upload completed (HTTP 200)")
        } else {
            print("[Extension REST] ERROR: Background upload HTTP \(http.statusCode) — queueing fallback")
            ExtensionSessionBridge.enqueuePendingOpenedFallback()
        }
    }
}
