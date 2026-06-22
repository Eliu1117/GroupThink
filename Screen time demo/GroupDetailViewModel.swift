//
//  GroupDetailViewModel.swift
//  Screen time demo
//
//  Loads member display names and handles group deletion for a single group.
//

import Combine
import FirebaseFirestore
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
    /// Live group doc — keeps settings/streaks fresh while this screen is open.
    @Published private(set) var liveGroup: Group?
    @Published private(set) var isUpdatingSettings = false

    private var groupListener: ListenerRegistration?

    deinit {
        groupListener?.remove()
    }

    // MARK: - Live group + settings

    func startObservingGroup(groupID: String) {
        guard groupListener == nil else { return }

        groupListener = GroupService.shared.observeGroup(groupID: groupID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let group):
                    self.liveGroup = group
                case .failure(let error):
                    print("[Groups] Group listener error: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopObservingGroup() {
        groupListener?.remove()
        groupListener = nil
    }

    /// Persists a single Bool setting (creator only — enforced in GroupService).
    func updateSetting(groupID: String, requesterUID: String, key: String, value: Bool) async {
        isUpdatingSettings = true
        defer { isUpdatingSettings = false }

        do {
            try await GroupService.shared.updateGroupSetting(
                groupID: groupID,
                requesterUID: requesterUID,
                key: key,
                value: value
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[Groups] Setting update failed: \(error.localizedDescription)")
        }
    }

    /// Persists a single Int setting (creator only — enforced in GroupService).
    func updateIntSetting(groupID: String, requesterUID: String, key: String, value: Int) async {
        isUpdatingSettings = true
        defer { isUpdatingSettings = false }

        do {
            try await GroupService.shared.updateGroupSetting(
                groupID: groupID,
                requesterUID: requesterUID,
                key: key,
                value: value
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[Groups] Int setting update failed: \(error.localizedDescription)")
        }
    }

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
