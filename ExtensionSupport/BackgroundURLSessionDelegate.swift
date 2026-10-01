//
//  BackgroundURLSessionDelegate.swift
//  ExtensionSupport
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

    // Parameter type must be `URLSession` (not `String`) to actually match
    // `URLSessionDelegate`'s optional requirement — a mismatched type here means this method
    // is never invoked by the system at all, silently dropping the completion handler and
    // the background session would never be told its events were drained.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let identifier = session.configuration.identifier ?? "unknown"
        print("[Extension REST] Background session finished events — \(identifier)")
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
