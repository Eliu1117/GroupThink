//
//  GroupDetailView.swift
//  Screen time demo
//

import SwiftUI
import UIKit

struct GroupDetailView: View {
    let group: Group
    let currentUserUID: String?

    @StateObject private var viewModel = GroupDetailViewModel()
    @State private var didCopyCode = false

    var body: some View {
        List {
            inviteCodeSection
            membersSection
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMembers(for: group)
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
            } else if let errorMessage = viewModel.errorMessage, viewModel.members.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                ForEach(viewModel.members) { member in
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.secondary)

                        Text(member.displayName)

                        if member.id == group.createdBy {
                            Text("Host")
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
