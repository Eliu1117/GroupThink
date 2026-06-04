//
//  GroupsListView.swift
//  Screen time demo
//

import SwiftUI

struct GroupsListView: View {
    let uid: String

    @EnvironmentObject private var account: AccountManager
    @StateObject private var viewModel = GroupsViewModel()

    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .navigationTitle("Study Halls")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showCreate = true } label: { Label("Create group", systemImage: "plus") }
                        Button { showJoin = true } label: { Label("Join with code", systemImage: "envelope") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateGroupView(viewModel: viewModel)
            }
            .sheet(isPresented: $showJoin) {
                JoinGroupView(viewModel: viewModel)
            }
            .onAppear { viewModel.start(uid: uid) }
        }
    }

    private var groupList: some View {
        List(viewModel.groups) { group in
            NavigationLink(value: group) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name).font(.headline)
                    Text("\(group.memberUids.count) member\(group.memberUids.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationDestination(for: StudyGroup.self) { group in
            GroupDetailView(group: group, uid: uid, displayName: account.currentUser?.displayName ?? "Studier")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No study halls yet", systemImage: "person.3")
        } description: {
            Text("Create a group or join one with an invite code to start studying together.")
        } actions: {
            Button("Create a group") { showCreate = true }
                .buttonStyle(.borderedProminent)
            Button("Join with a code") { showJoin = true }
        }
    }
}
