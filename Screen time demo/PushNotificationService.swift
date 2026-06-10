//
//  PushNotificationService.swift
//  Screen time demo
//
//  FCM registration and fcmTokens persistence on the user document.
//

import FirebaseAuth
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    private(set) var isRegistered = false

    private override init() {
        super.init()
    }

    func configureDelegates() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }

    /// Requests notification permission and registers for a remote token.
    func registerForPushNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])

            guard granted else {
                print("[FCM] Notification permission denied")
                return
            }

            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            print("[FCM] Registered for remote notifications")
        } catch {
            print("[FCM] Permission request failed: \(error.localizedDescription)")
        }
    }

    func handleTokenRefresh(_ token: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[FCM] Skipping token save — no authenticated user")
            return
        }

        do {
            try await UserService.shared.saveFCMToken(uid: uid, token: token)
            isRegistered = true
            print("[FCM] Saved token for \(uid)")
        } catch {
            print("[FCM] Token save failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - MessagingDelegate

extension PushNotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            await PushNotificationService.shared.handleTokenRefresh(fcmToken)
        }
    }
}
