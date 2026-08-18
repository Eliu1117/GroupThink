//
//  RootView.swift
//  Screen time demo
//

import FirebaseAuth
import FirebaseMessaging
import SwiftUI

struct RootView: View {
    /// Gates whether the one-time Profile Setup screen shows before MainTabView.
    private enum ProfileGateState: Equatable {
        case checking
        case needsSetup
        case complete
    }

    @StateObject private var authViewModel = AuthViewModel()
    @ObservedObject private var screenTimeAuth = AuthorizationManager.shared
    @ObservedObject private var appearanceSettings = AppearanceSettings.shared
    @State private var profileGateState: ProfileGateState = .checking

    var body: some View {
        SwiftUI.Group {
            if !authViewModel.isAuthenticated {
                LoginView()
            } else if !screenTimeAuth.isAuthorized {
                ScreenTimePermissionView()
            } else {
                switch profileGateState {
                case .checking:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .kawaiiBackground()
                case .needsSetup:
                    ProfileSetupView(isOnboarding: true) {
                        profileGateState = .complete
                    }
                case .complete:
                    MainTabView()
                }
            }
        }
        .environmentObject(authViewModel)
        .environmentObject(appearanceSettings)
        .preferredColorScheme(appearanceSettings.preferredColorScheme)
        .animation(.easeInOut, value: authViewModel.isAuthenticated)
        .animation(.easeInOut, value: screenTimeAuth.isAuthorized)
        .animation(.easeInOut, value: appearanceSettings.mode)
        .animation(.easeInOut, value: profileGateState)
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
        // Re-checks whenever Screen Time authorization flips true — covers both a fresh
        // sign-in (auth already true, this fires once authorization catches up) and a cold
        // launch where both are already true (the .task still fires once on first appear).
        .task(id: screenTimeAuth.isAuthorized) {
            guard authViewModel.isAuthenticated, screenTimeAuth.isAuthorized, let uid = authViewModel.user?.uid else { return }
            await checkProfileSetup(uid: uid)
        }
    }

    private func checkProfileSetup(uid: String) async {
        profileGateState = .checking
        let profiles = await UserService.shared.fetchProfiles(for: [uid])
        profileGateState = (profiles[uid]?.profileSetupCompleted == true) ? .complete : .needsSetup
    }
}

#Preview {
    RootView()
}
