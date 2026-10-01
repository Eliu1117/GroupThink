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
    /// Avatar/photo info for each member, keyed by UID — lets the Members list and Focus
    /// Roster show each person's actual chosen avatar instead of a generic placeholder icon.
    @Published private(set) var memberAvatars: [String: UserProfile] = [:]
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

        // `knownNames` (the Firebase Auth-derived name, used as an optimistic seed for the
        // current user before Firestore responds) must only ever be a *fallback* — applying
        // it AFTER the Firestore fetch used to let it clobber a real, user-chosen Profile
        // Setup `username` with the generic Auth name whenever the Auth name happened to be
        // non-placeholder (e.g. a real name from a non-Apple-relay sign-in). Seeding it first
        // and letting the Firestore-resolved names (which already prefer `username`) override
        // it fixes that, while still giving an immediate name before the fetch completes.
        var names: [String: String] = [:]
        for (uid, name) in knownNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "User", trimmed != "Member" else { continue }
            names[uid] = trimmed
        }

        // Names and avatars are independent reads of the same `users/{uid}` docs — fetch
        // them concurrently rather than sequentially.
        async let fetchedNames = UserService.shared.fetchDisplayNames(for: group.memberUids)
        async let fetchedProfiles = UserService.shared.fetchProfiles(for: group.memberUids)

        for (uid, name) in await fetchedNames {
            names[uid] = name
        }

        memberNames = names
        memberAvatars = await fetchedProfiles
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
