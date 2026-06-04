//
//  NotificationManager.swift
//  Screen time demo
//
//  Wraps UNUserNotificationCenter + Firebase Cloud Messaging. Registers for push,
//  tracks the FCM token, and persists it on the signed-in user document.
//

import FirebaseAuth
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var currentToken: String?
    @Published private(set) var isAuthorized = false

    private override init() {
        super.init()
    }

    /// Call once at launch from the app delegate.
    func configure() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            isAuthorized = false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Writes the current FCM token to the signed-in user, if both are available.
    func syncTokenForCurrentUser() async {
        guard let uid = Auth.auth().currentUser?.uid, let token = currentToken else { return }
        try? await UserService.shared.addFCMToken(uid: uid, token: token)
    }

    func setAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

extension NotificationManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.currentToken = fcmToken
            await self.syncTokenForCurrentUser()
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
