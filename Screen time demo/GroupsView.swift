//
//  GroupsView.swift
//  Screen time demo
//
//  Groups tab: real-time list, create/join sheets, navigation to detail.
//

import FirebaseAuth
import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = GroupsViewModel()

    @State private var showCreateGroup = false
    @State private var showJoinGroup = false

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if viewModel.isLoading && viewModel.groups.isEmpty {
                    loadingView
                } else if viewModel.groups.isEmpty {
                    emptyState
                } else {
                    groupsList
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.clearError()
                            showCreateGroup = true
                        } label: {
                            Label("Create Group", systemImage: "plus")
                        }

                        Button {
                            viewModel.clearError()
                            showJoinGroup = true
                        } label: {
                            Label("Join with Code", systemImage: "envelope")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView(viewModel: viewModel)
            }
            .sheet(isPresented: $showJoinGroup) {
                JoinGroupView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.startListening(userUID: authViewModel.user?.uid)
                Task { await authViewModel.syncProfileToFirestore() }
            }
            .onChange(of: authViewModel.user?.uid) { _, userUID in
                viewModel.startListening(userUID: userUID)
            }
        }
    }

    // MARK: - List

    private var groupsList: some View {
        List(viewModel.groups) { group in
            NavigationLink(value: group) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)

                    Text("\(group.memberUids.count) member\(group.memberUids.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationDestination(for: Group.self) { group in
            GroupDetailView(group: group, currentUserUID: authViewModel.user?.uid)
        }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.9), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Empty / loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading groups…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Groups Yet", systemImage: "person.3")
        } description: {
            Text("Create a study hall group or join one with an invite code.")
        } actions: {
            Button("Create Group") {
                viewModel.clearError()
                showCreateGroup = true
            }
            .buttonStyle(.borderedProminent)

            Button("Join with Code") {
                viewModel.clearError()
                showJoinGroup = true
            }
        }
    }
}

#Preview {
    GroupsView()
        .environmentObject(AuthViewModel())
}
