//
//  GroupDetailViewModel.swift
//  Screen time demo
//
//  Loads member display names and handles group deletion for a single group.
//

import Combine
import Foundation

struct GroupMember: Identifiable, Equatable {
    let id: String
    let displayName: String
}

@MainActor
final class GroupDetailViewModel: ObservableObject {
    @Published private(set) var members: [GroupMember] = []
    @Published private(set) var memberNames: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isDeleting = false
    @Published private(set) var errorMessage: String?

    func loadMembers(for group: Group, knownNames: [String: String] = [:]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var names = await UserService.shared.fetchDisplayNames(for: group.memberUids)

        for (uid, name) in knownNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "User", trimmed != "Member" else { continue }
            names[uid] = trimmed
        }

        memberNames = names
        members = group.memberUids.map { uid in
            GroupMember(id: uid, displayName: names[uid] ?? "Member")
        }

        let resolvedCount = members.filter { $0.displayName != "Member" }.count
        print("[Groups] Resolved \(resolvedCount)/\(members.count) member name(s) for group \(group.id)")
    }

    func deleteGroup(groupID: String, requesterUID: String) async -> Bool {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await GroupService.shared.deleteGroup(groupID: groupID, requesterUID: requesterUID)
            print("[Groups] Group \(groupID) deleted by \(requesterUID)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Groups] Delete failed: \(error.localizedDescription)")
            return false
        }
    }
}
