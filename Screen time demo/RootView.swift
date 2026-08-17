//
//  RootView.swift
//  Screen time demo
//

import FirebaseMessaging
import SwiftUI

struct RootView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @ObservedObject private var screenTimeAuth = AuthorizationManager.shared
    @ObservedObject private var appearanceSettings = AppearanceSettings.shared

    var body: some View {
        SwiftUI.Group {
            if !authViewModel.isAuthenticated {
                LoginView()
            } else if !screenTimeAuth.isAuthorized {
                ScreenTimePermissionView()
            } else {
                MainTabView()
            }
        }
        .environmentObject(authViewModel)
        .environmentObject(appearanceSettings)
        .preferredColorScheme(appearanceSettings.preferredColorScheme)
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
        .animation(.easeInOut, value: screenTimeAuth.isAuthorized)
        .animation(.easeInOut, value: appearanceSettings.mode)
        .task(id: authViewModel.isAuthenticated) {
            guard authViewModel.isAuthenticated else { return }
            await PushNotificationService.shared.registerForPushNotifications()
            do {
                let token = try await Messaging.messaging().token()
                await PushNotificationService.shared.handleTokenRefresh(token)
            } catch {
                // Expected if APNs registration hasn't completed yet — the delegate
                // callback and the APNs-registration hook will retry the save.
                print("[FCM] Token fetch on auth failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    RootView()
}
