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
        // Delegates must be attached synchronously, before FCM vends the initial token.
        PushNotificationService.shared.configureDelegates()
        Task {
            await ExtensionAuthTokenBridge.persistIDTokenForExtension(forcingRefresh: false)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        print("[FCM] APNs device token registered")

        // The APNs token is the prerequisite for an FCM token — fetch and persist now.
        Task {
            do {
                let token = try await Messaging.messaging().token()
                await PushNotificationService.shared.handleTokenRefresh(token)
            } catch {
                print("[FCM] Token fetch after APNs registration failed: \(error.localizedDescription)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[FCM] APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundURLSessionRelauncher.handleEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
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
