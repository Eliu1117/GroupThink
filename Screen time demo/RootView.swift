//
//  RootView.swift
//  Screen time demo
//

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
    }
}

#Preview {
    RootView()
}
