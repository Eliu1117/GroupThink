//
//  ProfileView.swift
//  Screen time demo
//

import FirebaseAuth
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var appearanceSettings: AppearanceSettings
    @StateObject private var profileViewModel = ProfileViewModel()
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            List {
                profileHeaderSection

                if profileViewModel.isLoading && profileViewModel.profile == nil {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if let profile = profileViewModel.profile {
                    statsSection(profile)
                }

                editProfileSection

                appearanceSection

                if let errorMessage = profileViewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        profileViewModel.startListening(userID: nil)
                        authViewModel.signOut()
                    }
                    .tint(.red)
                }
            }
            .kawaiiListBackground()
            .navigationTitle("Profile")
            .onAppear {
                Task {
                    await authViewModel.syncProfileToFirestore()
                    profileViewModel.startListening(userID: authViewModel.user?.uid)
                }
            }
            .onChange(of: authViewModel.user?.uid) { _, userID in
                profileViewModel.startListening(userID: userID)
            }
            .sheet(isPresented: $showEditProfile) {
                ProfileSetupView(isOnboarding: false)
            }
        }
    }

    // MARK: - Sections

    private var profileHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                avatarView

                VStack(spacing: 4) {
                    Text(displayName)
                        .font(.theme.heading(20))
                        .foregroundStyle(Color.theme.text)

                    if let email = authViewModel.user?.email {
                        Text(email)
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func statsSection(_ profile: UserProfile) -> some View {
        Section {
            HStack(spacing: 12) {
                KawaiiStatBlock(
                    icon: "clock.fill",
                    iconTint: Color.theme.primary,
                    value: "\(profile.focusMinutes)",
                    label: "Focus Minutes"
                )
                KawaiiStatBlock(
                    icon: "flame.fill",
                    iconTint: Color.theme.secondary,
                    value: "\(profile.currentStreak)",
                    label: "Day Streak"
                )
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Stats")
                .foregroundStyle(Color.theme.text.opacity(0.6))
        }
    }

    private var editProfileSection: some View {
        Section {
            KawaiiListRow(
                icon: "pencil",
                iconTint: Color.theme.secondary,
                title: "Edit Profile",
                subtitle: "Update your username and avatar"
            ) {
                showEditProfile = true
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Appearance", systemImage: "paintbrush.fill")
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text)

                Picker("Appearance", selection: $appearanceSettings.mode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Settings")
                .foregroundStyle(Color.theme.text.opacity(0.6))
        } footer: {
            Text("Auto follows your iPhone’s light or dark mode setting.")
                .foregroundStyle(Color.theme.text.opacity(0.55))
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        let photoURL = profileViewModel.profile?.photoURL ?? authViewModel.user?.photoURL

        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.theme.surface, lineWidth: 4))
        } else if let assetName = profileViewModel.profile?.avatarAssetName,
                  let avatarOption = AvatarOption(rawValue: assetName) {
            Image(avatarOption.assetName)
                .resizable()
                .scaledToFit()
                .padding(16)
                .frame(width: 88, height: 88)
                .background(Color.theme.secondary.opacity(0.18))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.theme.surface, lineWidth: 4))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.theme.primary.opacity(0.4))
            .frame(width: 88, height: 88)
            .overlay(Circle().stroke(Color.theme.surface, lineWidth: 4))
            .overlay {
                Text(initials)
                    .font(.theme.heading(24))
                    .foregroundStyle(Color.theme.text)
            }
    }

    /// Prefers the user-chosen `username` once Profile Setup is complete; otherwise falls
    /// back to the original Apple/Firebase-derived `displayName` used before this feature.
    private var displayName: String {
        if let profile = profileViewModel.profile, profile.profileSetupCompleted {
            return profile.username
        }
        return profileViewModel.profile?.displayName
            ?? authViewModel.user?.displayName
            ?? "User"
    }

    private var initials: String {
        let name = displayName
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
        .environmentObject(AppearanceSettings.shared)
}
