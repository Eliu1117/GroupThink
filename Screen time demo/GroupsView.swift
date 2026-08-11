//
//  GroupsView.swift
//  Screen time demo
//
//  Groups tab: real-time list, create/join sheets, navigation to detail.
//

import FirebaseAuth
import SwiftUI

/// Typed navigation destination that carries whether the group should auto-start a session.
struct GroupNavigation: Hashable {
    let group: Group
    let autoStart: Bool
}

struct GroupsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = GroupsViewModel()

    @State private var showCreateGroup = false
    @State private var showJoinGroup = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            SwiftUI.Group {
                if viewModel.isLoading && viewModel.groups.isEmpty {
                    loadingView
                } else if viewModel.groups.isEmpty {
                    emptyState
                } else {
                    groupsList
                }
            }
            .kawaiiBackground()
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
            // When a group is freshly created, navigate to it with auto-start enabled
            // as soon as the Firestore listener delivers it to the list.
            .onChange(of: viewModel.groups) { _, groups in
                guard let pendingID = viewModel.pendingNavigationGroupID,
                      let group = groups.first(where: { $0.id == pendingID })
                else { return }
                navigationPath.append(GroupNavigation(group: group, autoStart: true))
                viewModel.clearPendingNavigation()
            }
        }
    }

    // MARK: - List

    private var groupsList: some View {
        List(viewModel.groups) { group in
            NavigationLink(value: GroupNavigation(group: group, autoStart: false)) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.theme.secondary.opacity(0.4))
                            .frame(width: 40, height: 40)
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundStyle(Color.theme.text)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.theme.headline())
                            .foregroundStyle(Color.theme.text)

                        Text("\(group.memberUids.count) member\(group.memberUids.count == 1 ? "" : "s")")
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .kawaiiListBackground()
        .navigationDestination(for: GroupNavigation.self) { nav in
            GroupDetailView(
                group: nav.group,
                currentUserUID: authViewModel.user?.uid,
                autoStartSession: nav.autoStart
            )
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
                .tint(Color.theme.text)
            Text("Loading groups…")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .kawaiiBackground()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.theme.text.opacity(0.35))

            VStack(spacing: 6) {
                Text("No Groups Yet")
                    .font(.theme.heading(20))
                    .foregroundStyle(Color.theme.text)
                Text("Create a study hall group or join one with an invite code.")
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button("Create Group") {
                    viewModel.clearError()
                    showCreateGroup = true
                }
                .buttonStyle(.kawaiiPrimary())

                Button("Join with Code") {
                    viewModel.clearError()
                    showJoinGroup = true
                }
                .buttonStyle(.kawaiiOutlined)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .kawaiiBackground()
    }
}

#Preview {
    GroupsView()
        .environmentObject(AuthViewModel())
}
