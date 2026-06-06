//
//  ProfileView.swift
//  Screen time demo
//

import FirebaseAuth
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var profileViewModel = ProfileViewModel()

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
                }
            }
            .navigationTitle("Profile")
            .onAppear {
                profileViewModel.startListening(userID: authViewModel.user?.uid)
            }
            .onChange(of: authViewModel.user?.uid) { _, userID in
                profileViewModel.startListening(userID: userID)
            }
        }
    }

    // MARK: - Sections

    private var profileHeaderSection: some View {
        Section {
            HStack(spacing: 16) {
                avatarView

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.title2.bold())

                    if let email = authViewModel.user?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }

    private func statsSection(_ profile: UserProfile) -> some View {
        Section("Stats") {
            LabeledContent {
                Text("\(profile.focusMinutes)")
                    .fontWeight(.semibold)
            } label: {
                Label("Focus Minutes", systemImage: "clock.fill")
            }

            LabeledContent {
                Text("\(profile.currentStreak)")
                    .fontWeight(.semibold)
            } label: {
                Label("Current Streak", systemImage: "flame.fill")
            }
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
            .frame(width: 72, height: 72)
            .clipShape(Circle())
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 72, height: 72)
            .overlay {
                Text(initials)
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
            }
    }

    private var displayName: String {
        profileViewModel.profile?.displayName
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
}
