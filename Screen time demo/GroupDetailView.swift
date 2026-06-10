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

    /// Live group doc when available; falls back to the pushed snapshot.
    private var currentGroup: Group {
        viewModel.liveGroup ?? group
    }

    private var isCreator: Bool {
        guard let currentUserUID else { return false }
        return currentGroup.createdBy == currentUserUID
    }

    /// True when the current user is allowed to start a new session.
    private var canStartSession: Bool {
        guard currentUserUID != nil else { return false }
        return !currentGroup.creatorOnlyStart || isCreator
    }

    var body: some View {
        List {
            if sessionViewModel.session != nil {
                SessionView(
                    viewModel: sessionViewModel,
                    memberNames: sessionViewModel.participantNames
                )
            }

            if sessionViewModel.session == nil {
                sessionActionsSection
            }

            groupSettingsSection
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
        .navigationTitle(currentGroup.name)
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
        .sheet(item: $sessionViewModel.sessionSummary) { summary in
            SessionSummaryView(summary: summary)
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

            sessionViewModel.updateGroupSettings(group: currentGroup)

            var knownNames: [String: String] = [:]
            if let currentUserUID {
                knownNames[currentUserUID] = authViewModel.resolvedProfileDisplayName
            }
            await viewModel.loadMembers(for: group, knownNames: knownNames)

            sessionViewModel.seedParticipantNames(viewModel.memberNames)
        }
        .onAppear {
            sessionViewModel.configure(groupID: group.id, currentUID: currentUserUID)
            viewModel.startObservingGroup(groupID: group.id)
        }
        .onChange(of: viewModel.liveGroup) { _, liveGroup in
            if let liveGroup {
                sessionViewModel.updateGroupSettings(group: liveGroup)
            }
        }
        // Session listener and countdown stay alive while subviews (e.g. Leaderboard)
        // are pushed; cleanup happens in the ViewModels' deinit when truly popped.
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
            .disabled(!canStartSession || sessionViewModel.isSubmitting)
        } footer: {
            if !canStartSession {
                Text("Only the group creator can start a session.")
            } else if currentGroup.strictMode {
                Text("Strict mode is on: all apps will be blocked except each member's whitelist (set on the Home tab).")
            } else {
                Text("Host a focused study session for this group. Configure your blocklist on the Home tab first.")
            }
        }
    }

    // MARK: - Group settings

    private var groupSettingsSection: some View {
        Section {
            settingRow(
                key: "strictMode",
                value: currentGroup.strictMode,
                title: "Strict Mode",
                symbol: "lock.shield.fill"
            )
            settingRow(
                key: "requireBlocklist",
                value: currentGroup.requireBlocklist,
                title: "Require Blocklist",
                symbol: "checklist"
            )
            settingRow(
                key: "allowLateJoin",
                value: currentGroup.allowLateJoin,
                title: "Allow Late Join",
                symbol: "person.badge.clock.fill"
            )
            settingRow(
                key: "creatorOnlyStart",
                value: currentGroup.creatorOnlyStart,
                title: "Creator-Only Start",
                symbol: "crown.fill"
            )
        } header: {
            Text("Group Settings")
        } footer: {
            if isCreator {
                Text("Strict mode blocks every app on members' devices during sessions, except apps they whitelist on the Home tab.")
            } else {
                Text("Only the group creator can change these settings.")
            }
        }
    }

    @ViewBuilder
    private func settingRow(key: String, value: Bool, title: String, symbol: String) -> some View {
        if isCreator {
            Toggle(isOn: settingBinding(key: key, value: value)) {
                Label(title, systemImage: symbol)
            }
            .disabled(viewModel.isUpdatingSettings)
        } else {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(value ? .green : .secondary)
            }
        }
    }

    private func settingBinding(key: String, value: Bool) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { newValue in
                guard let currentUserUID else { return }
                Task {
                    await viewModel.updateSetting(
                        groupID: group.id,
                        requesterUID: currentUserUID,
                        key: key,
                        value: newValue
                    )
                }
            }
        )
    }

    // MARK: - Leaderboard (Phase 5)

    private var leaderboardSection: some View {
        Section {
            NavigationLink {
                GroupLeaderboardView(
                    group: currentGroup,
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
                Text(currentGroup.inviteCode)
                    .font(.title2.monospaced().bold())

                Spacer()

                Button {
                    UIPasteboard.general.string = currentGroup.inviteCode
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
        Section("Members (\(currentGroup.memberUids.count))") {
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

                        if member.id == currentGroup.createdBy {
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
        viewModel.stopObservingGroup()

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
