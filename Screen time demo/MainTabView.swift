//
//  MainTabView.swift
//  Screen time demo
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var navState: AppNavigationState

    var body: some View {
        TabView {
            // Each tab's root content is keyed on `refreshToken` so "Apply Theme" (see
            // `ThemeSettings`) can force a guaranteed, full rebuild of every button/card in
            // the app — SwiftUI's live propagation of theme changes to already-on-screen
            // content proved unreliable in practice. The Settings sheet below is attached to
            // `MainTabView` itself, OUTSIDE this reset, so it's completely unaffected and the
            // user never loses their place while applying a theme.
            ContentView()
                .id(themeSettings.refreshToken)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            GroupsView()
                .id(themeSettings.refreshToken)
                .tabItem {
                    Label("Groups", systemImage: "person.3.fill")
                }

            ProfileView()
                .id(themeSettings.refreshToken)
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
        }
        .sheet(isPresented: $navState.isSettingsPresented) {
            // `SettingsView` owns its own toolbar (title + Done) so both can read
            // `Color.theme.*` reactively against the in-progress preview — see
            // `SettingsView`'s doc comment on its `.toolbar` for why that matters.
            NavigationStack {
                SettingsView()
            }
        }
        // App-wide safety net: flush any queued "opened blocked app" events whenever the app
        // becomes active, regardless of which tab is showing. A specific group's screen may
        // not be on-screen (or its session may have already ended) when the user returns, so
        // this must not depend on GroupDetailView/SessionViewModel being alive to fire.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await PendingOpenedEventFlusher.flush() }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(ThemeSettings.shared)
        .environmentObject(AppNavigationState.shared)
}
