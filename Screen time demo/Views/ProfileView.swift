//
//  ProfileView.swift
//  Screen time demo
//

import FamilyControls
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var account: AccountManager
    @StateObject private var authManager = AuthorizationManager.shared
    @StateObject private var blocklist = BlocklistStore.shared
    @StateObject private var viewModel = ProfileViewModel()

    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                statsSection
                blockingSection
                notificationsSection
                aboutSection
                signOutSection
            }
            .navigationTitle("Profile")
            .familyActivityPicker(isPresented: $showPicker, selection: $blocklist.selection)
            .task {
                authManager.refreshAuthorizationStatus()
                await viewModel.refresh()
            }
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(account.currentUser?.displayName ?? "Studier")
                        .font(.headline)
                    Text("Signed in with Apple")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsSection: some View {
        Section("Your stats") {
            LabeledContent("Focus minutes", value: "\(account.currentUser?.stats.focusMinutes ?? 0)")
            LabeledContent("Current streak", value: "\(account.currentUser?.stats.currentStreak ?? 0) days")
        }
    }

    private var blockingSection: some View {
        Section {
            if authManager.isAuthorized {
                Button {
                    showPicker = true
                } label: {
                    LabeledContent("Apps to block", value: "\(blocklist.selectedCount) selected")
                }
            } else {
                Button("Allow Screen Time access") {
                    Task { await authManager.requestAuthorization() }
                }
            }
            NavigationLink("Blocking test (Phase 0 demo)") {
                BlockingDemoView()
            }
        } header: {
            Text("Blocking")
        } footer: {
            Text("You choose which of your own apps get blocked during a study hall. These stay on your device.")
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            if viewModel.notificationsEnabled {
                LabeledContent("Push notifications", value: "On")
            } else {
                Button("Enable push notifications") {
                    Task { await viewModel.enableNotifications() }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Study Hall blocks distractions during group focus sessions. A determined user can always bypass it — the point is staying accountable to your friends.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var signOutSection: some View {
        Section {
            Button("Sign out", role: .destructive) {
                account.signOut()
            }
        }
    }
}
