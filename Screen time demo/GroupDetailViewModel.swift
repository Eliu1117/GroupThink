//
//  GroupDetailViewModel.swift
//  Screen time demo
//
//  Loads member display names for a single group.
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
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func loadMembers(for group: Group) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let names = try await GroupService.shared.fetchMemberDisplayNames(for: group.memberUids)
            members = group.memberUids.map { uid in
                GroupMember(id: uid, displayName: names[uid] ?? "Member")
            }
            print("[Groups] Resolved \(members.count) member name(s) for group \(group.id)")
        } catch {
            errorMessage = error.localizedDescription
            members = group.memberUids.map { GroupMember(id: $0, displayName: "Member") }
            print("[Groups] Member fetch failed: \(error.localizedDescription)")
        }
    }
}
