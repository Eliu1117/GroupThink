//
//  GroupsViewModel.swift
//  Screen time demo
//
//  Drives the groups list, create-group, and join-group flows.
//

import Combine
import FirebaseFirestore

@MainActor
final class GroupsViewModel: ObservableObject {
    @Published private(set) var groups: [Group] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    /// Set after a successful creation so GroupsView can navigate directly to the new group.
    @Published private(set) var pendingNavigationGroupID: String?

    private var listener: ListenerRegistration?
    private var userUID: String?

    deinit {
        listener?.remove()
    }

    func startListening(userUID: String?) {
        listener?.remove()
        listener = nil
        groups = []
        errorMessage = nil
        self.userUID = userUID

        guard let userUID else {
            isLoading = false
            return
        }

        isLoading = true
        print("[Groups] Starting listener for uid \(userUID)")

        listener = GroupService.shared.observeGroups(for: userUID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success(let groups):
                    self.groups = groups
                    self.isLoading = false
                    self.errorMessage = nil
                    print("[Groups] Loaded \(groups.count) group(s)")

                case .failure(let error):
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    print("[Groups] Listener error: \(error.localizedDescription)")
                }
            }
        }
    }

    func createGroup(name: String) async -> Bool {
        guard let userUID else {
            errorMessage = GroupServiceError.notSignedIn.localizedDescription
            return false
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a group name."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let groupID = try await GroupService.shared.createGroup(name: trimmed, creatorUID: userUID)
            pendingNavigationGroupID = groupID
            print("[Groups] Created group \(groupID)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Groups] Create failed: \(error.localizedDescription)")
            return false
        }
    }

    func joinGroup(inviteCode: String) async -> Bool {
        guard let userUID else {
            errorMessage = GroupServiceError.notSignedIn.localizedDescription
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let group = try await GroupService.shared.joinGroup(inviteCode: inviteCode, userUID: userUID)
            print("[Groups] Joined group \(group.id)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[Groups] Join failed: \(error.localizedDescription)")
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearPendingNavigation() {
        pendingNavigationGroupID = nil
    }
}
