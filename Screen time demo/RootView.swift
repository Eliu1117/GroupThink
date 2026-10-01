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
        // Re-checks whenever auth state, Screen Time authorization, OR the signed-in uid
        // changes. `.task(id:)` only restarts when its id's VALUE changes — keying this on
        // `screenTimeAuth.isAuthorized` alone was a bug: for a returning user that value is
        // already `true` at cold launch, so the task fires once, immediately, before
        // `authViewModel.isAuthenticated` (set asynchronously by Firebase's auth-state
        // listener) has necessarily flipped true yet. The guard would fail, the task would
        // exit having done nothing, and since `isAuthorized`'s value never changed again,
        // the task would never re-fire — leaving `profileGateState` stuck at `.checking`
        // (an infinite spinner) with no crash. Combining every dependency into the id fixes
        // this regardless of which async signal (auth listener vs. authorization refresh)
        // happens to resolve first.
        .task(id: profileGateTaskID) {
            guard authViewModel.isAuthenticated, screenTimeAuth.isAuthorized, let uid = authViewModel.user?.uid else { return }
            await checkProfileSetup(uid: uid)
        }
    }

    /// Combines every piece of state `profileGateTaskID`'s task depends on into one
    /// `Equatable` id, so the task reliably restarts no matter which async signal
    /// (Firebase auth listener vs. Screen Time authorization refresh) resolves last.
    private var profileGateTaskID: String {
        "\(authViewModel.isAuthenticated)|\(screenTimeAuth.isAuthorized)|\(authViewModel.user?.uid ?? "")"
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
