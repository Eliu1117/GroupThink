//
//  GroupDetailView.swift
//  Screen time demo
//

import SwiftUI
import UIKit

struct GroupDetailView: View {
    let group: Group
    let currentUserUID: String?

    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = GroupDetailViewModel()
    @StateObject private var sessionViewModel = SessionViewModel()

    @State private var didCopyCode = false
    @State private var showDeleteConfirmation = false

    private var isCreator: Bool {
        guard let currentUserUID else { return false }
        return group.createdBy == currentUserUID
    }

    var body: some View {
        List {
            if sessionViewModel.session != nil {
                SessionView(
                    viewModel: sessionViewModel,
                    memberNames: viewModel.memberNames
                )
            }

            if sessionViewModel.session == nil {
                sessionActionsSection
            }

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
        .task {
            await viewModel.loadMembers(for: group)
        }
        .onAppear {
            sessionViewModel.configure(groupID: group.id, currentUID: currentUserUID)
        }
        .onDisappear {
            sessionViewModel.stopListening()
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
            .disabled(sessionViewModel.isSubmitting || currentUserUID == nil)
        } footer: {
            Text("Host a focused study session for this group. Configure your blocklist on the Home tab first.")
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
    }
}
