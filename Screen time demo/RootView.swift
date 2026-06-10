//
//  RootView.swift
//  Screen time demo
//

import FirebaseMessaging
import SwiftUI

struct RootView: View {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some View {
        SwiftUI.Group {
            if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .environmentObject(authViewModel)
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
        .task(id: authViewModel.isAuthenticated) {
            guard authViewModel.isAuthenticated else { return }
            await PushNotificationService.shared.registerForPushNotifications()
            if let token = try? await Messaging.messaging().token() {
                await PushNotificationService.shared.handleTokenRefresh(token)
            }
        }
    }
}

#Preview {
    RootView()
}
