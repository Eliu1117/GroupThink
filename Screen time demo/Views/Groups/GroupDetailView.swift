//
//  GroupDetailView.swift
//  Screen time demo
//
//  Group home: invite code, members, and the live study-hall session.
//

import SwiftUI
import UIKit

struct GroupDetailView: View {
    let group: StudyGroup
    let uid: String
    let displayName: String

    @StateObject private var session: SessionViewModel

    init(group: StudyGroup, uid: String, displayName: String) {
        self.group = group
        self.uid = uid
        self.displayName = displayName
        _session = StateObject(wrappedValue: SessionViewModel(group: group, uid: uid, displayName: displayName))
    }

    var body: some View {
        List {
            inviteSection
            SessionSectionView(session: session)
            membersSection
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    private var inviteSection: some View {
        Section("Invite code") {
            HStack {
                Text(group.inviteCode)
                    .font(.title2.monospaced().bold())
                Spacer()
                Button {
                    UIPasteboard.general.string = group.inviteCode
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private var membersSection: some View {
        Section("Members (\(group.memberUids.count))") {
            ForEach(group.memberUids, id: \.self) { memberUid in
                MemberRow(uid: memberUid, isYou: memberUid == uid)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })
    }
}

private struct MemberRow: View {
    let uid: String
    let isYou: Bool

    @State private var name: String?

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill").foregroundStyle(.secondary)
            Text(name ?? "…")
            if isYou {
                Text("You").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            name = (try? await UserService.shared.fetchUser(uid: uid))?.displayName ?? "Member"
        }
    }
}
