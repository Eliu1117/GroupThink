//
//  GroupsViewModel.swift
//  Screen time demo
//
//  Drives the list of groups the signed-in user belongs to.
//

import FirebaseFirestore
import Foundation

@MainActor
final class GroupsViewModel: ObservableObject {
    @Published private(set) var groups: [StudyGroup] = []
    @Published var errorMessage: String?
    @Published var isWorking = false

    private var listener: ListenerRegistration?
    private var uid: String?

    func start(uid: String) {
        guard self.uid != uid else { return }
        self.uid = uid
        listener?.remove()
        listener = GroupService.shared.observeGroups(for: uid) { [weak self] groups in
            Task { @MainActor in
                self?.groups = groups.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        uid = nil
        groups = []
    }

    func createGroup(name: String) async -> Bool {
        guard let uid else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Give your group a name."
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await GroupService.shared.createGroup(name: trimmed, ownerUid: uid)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func joinGroup(inviteCode: String) async -> Bool {
        guard let uid else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await GroupService.shared.joinGroup(inviteCode: inviteCode, uid: uid)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    deinit {
        listener?.remove()
    }
}
