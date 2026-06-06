//
//  MainTabView.swift
//  Screen time demo
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            GroupsPlaceholderView()
                .tabItem {
                    Label("Groups", systemImage: "person.3.fill")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
        }
    }
}

private struct GroupsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Groups Yet",
                systemImage: "person.3",
                description: Text("Create or join a study hall group — coming in Phase 2.")
            )
            .navigationTitle("Groups")
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}
