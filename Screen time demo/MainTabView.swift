//
//  MainTabView.swift
//  Screen time demo
//

import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            GroupsView()
                .tabItem {
                    Label("Groups", systemImage: "person.3.fill")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
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
}
