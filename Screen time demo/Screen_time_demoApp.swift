//
//  Screen_time_demoApp.swift
//  Screen time demo
//
//  Created by Ethan Liu on 6/1/26.
//

import FirebaseAuth
import FirebaseCore
import FirebaseMessaging
import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        FirebaseAuthConfigurator.configureSharedKeychainAccess()
        Task {
            await ExtensionAuthTokenBridge.persistIDTokenForExtension(forcingRefresh: false)
        }
        Task { @MainActor in
            PushNotificationService.shared.configureDelegates()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        print("[FCM] APNs device token registered")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[FCM] APNs registration failed: \(error.localizedDescription)")
    }
}

@main
struct Screen_time_demoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
