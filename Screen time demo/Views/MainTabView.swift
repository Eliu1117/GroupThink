//
//  MainTabView.swift
//  Screen time demo
//

import SwiftUI

struct MainTabView: View {
    let uid: String

    var body: some View {
        TabView {
            GroupsListView(uid: uid)
                .tabItem { Label("Groups", systemImage: "person.3.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
