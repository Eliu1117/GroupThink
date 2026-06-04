//
//  RootView.swift
//  Screen time demo
//
//  Top-level router: shows the sign-in screen or the main app based on auth state.
//

import SwiftUI

struct RootView: View {
    @StateObject private var account = AccountManager.shared

    var body: some View {
        Group {
            switch account.authState {
            case .loading:
                ProgressView("Loading…")
            case .signedOut:
                LoginView()
            case let .signedIn(uid):
                MainTabView(uid: uid)
            }
        }
        .environmentObject(account)
        .animation(.default, value: isSignedIn)
    }

    private var isSignedIn: Bool {
        if case .signedIn = account.authState { return true }
        return false
    }
}

#Preview {
    RootView()
}
