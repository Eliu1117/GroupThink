//
//  GroupDetailView.swift
//  Screen time demo
//

import SwiftUI
import UIKit

struct GroupDetailView: View {
    let group: Group
    let currentUserUID: String?

    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = GroupDetailViewModel()
    @StateObject private var sessionViewModel = SessionViewModel()

    @State private var didCopyCode = false
    @State private var showDeleteConfirmation = false

    private var isCreator: Bool {
        guard let currentUserUID else { return false }
        return group.createdBy == currentUserUID
    }

    /// GRO-20: True when the current user is allowed to start a new session.
    private var canStartSession: Bool {
        guard currentUserUID != nil else { return false }
        return !group.creatorOnlyStart || isCreator
    }

    var body: some View {
        List {
            if sessionViewModel.session != nil {
                SessionView(
                    viewModel: sessionViewModel,
                    // GRO-21: Use participant names hydrated by SessionViewModel so
                    // names for late-joining members are always up to date.
                    memberNames: sessionViewModel.participantNames
                )
            }

            if sessionViewModel.session == nil {
                sessionActionsSection
            }

            leaderboardSection
            inviteCodeSection
            membersSection

            if isCreator {
                deleteGroupSection
            }

            if let sessionError = sessionViewModel.errorMessage {
                Section {
                    Text(sessionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let groupError = viewModel.errorMessage {
                Section {
                    Text(groupError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete Group?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                Task { await deleteGroup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to permanently delete this group? This action cannot be undone.")
        }
        .overlay {
            if viewModel.isDeleting || sessionViewModel.isSubmitting {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task(id: group.memberUids) {
            await authViewModel.syncProfileToFirestore()

            // GRO-9/14/20: Sync group settings into the session VM.
            sessionViewModel.updateGroupSettings(group: group)

            var knownNames: [String: String] = [:]
            if let currentUserUID {
                knownNames[currentUserUID] = authViewModel.resolvedProfileDisplayName
            }
            await viewModel.loadMembers(for: group, knownNames: knownNames)

            // GRO-21: Seed resolved names into SessionViewModel so the roster
            // immediately shows real names without an extra Firestore round-trip.
            sessionViewModel.seedParticipantNames(viewModel.memberNames)
        }
        .onAppear {
            sessionViewModel.configure(groupID: group.id, currentUID: currentUserUID)
        }
        // GRO-19: onDisappear no longer calls stopListening().
        // The countdown and session listener are long-lived in the @StateObject ViewModel
        // and persist while GroupDetailView is in the navigation stack (e.g. when the
        // Leaderboard subview is pushed). Cleanup happens in SessionViewModel.deinit
        // when the view is truly popped from the stack.
        .onChange(of: scenePhase) { _, newPhase in
            sessionViewModel.handleScenePhase(newPhase)
        }
    }

    // MARK: - Session actions

    private var sessionActionsSection: some View {
        Section {
            Button {
                Task { await sessionViewModel.createSession() }
            } label: {
                Label("Start Study Hall", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // GRO-20: Disabled when creatorOnlyStart is true and user is not the creator.
            .disabled(!canStartSession || sessionViewModel.isSubmitting)
        } footer: {
            if !canStartSession {
                Text("Only the group creator can start a session.")
            } else {
                Text("Host a focused study session for this group. Configure your blocklist on the Home tab first.")
            }
        }
    }

    // MARK: - Leaderboard (Phase 5)

    private var leaderboardSection: some View {
        Section {
            NavigationLink {
                GroupLeaderboardView(
                    group: group,
                    currentUserUID: currentUserUID,
                    memberNames: viewModel.memberNames
                )
            } label: {
                Label("Leaderboard", systemImage: "trophy.fill")
            }
        }
    }

    // MARK: - Invite code

    private var inviteCodeSection: some View {
        Section("Invite code") {
            HStack {
                Text(group.inviteCode)
                    .font(.title2.monospaced().bold())

                Spacer()

                Button {
                    UIPasteboard.general.string = group.inviteCode
                    didCopyCode = true
                } label: {
                    Label(didCopyCode ? "Copied" : "Copy", systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Copy invite code")
            }

            Text("Share this code so friends can join your study hall.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        Section("Members (\(group.memberUids.count))") {
            if viewModel.isLoading && viewModel.members.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                ForEach(viewModel.members) { member in
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.secondary)

                        Text(member.displayName)

                        if member.id == group.createdBy {
                            Text("Creator")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }

                        if member.id == currentUserUID {
                            Text("You")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Delete

    private var deleteGroupSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Group", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isDeleting)
        }
    }

    private func deleteGroup() async {
        guard let currentUserUID else { return }

        sessionViewModel.stopListening()

        if await viewModel.deleteGroup(groupID: group.id, requesterUID: currentUserUID) {
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(
            group: Group(
                id: "preview",
                name: "Finals Crew",
                inviteCode: "K7Q2Z9",
                createdBy: "user1",
                memberUids: ["user1", "user2"]
            ),
            currentUserUID: "user1"
        )
        .environmentObject(AuthViewModel())
    }
}
