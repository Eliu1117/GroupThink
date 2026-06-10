//
//  GroupLeaderboardViewModel.swift
//  Screen time demo
//
//  Phase 5 — loads member stats for a group and ranks them by focus minutes.
//

import Combine
import FirebaseFirestore
import Foundation

struct LeaderboardEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
    let focusMinutes: Int
    let currentStreak: Int
}

@MainActor
final class GroupLeaderboardViewModel: ObservableObject {
    @Published private(set) var entries: [LeaderboardEntry] = []
    @Published private(set) var groupStreak: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()

    func load(group: Group, knownNames: [String: String] = [:]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Refresh the group doc so the streak reflects the latest session.
        groupStreak = await fetchLatestGroupStreak(groupID: group.id) ?? group.currentGroupStreak

        let profiles = await UserService.shared.fetchProfiles(for: group.memberUids)

        entries = group.memberUids
            .map { uid -> LeaderboardEntry in
                let profile = profiles[uid]
                let name = knownNames[uid]
                    ?? profile.map(\.displayName)
                    ?? "Member"
                return LeaderboardEntry(
                    id: uid,
                    displayName: name,
                    focusMinutes: profile?.focusMinutes ?? 0,
                    currentStreak: profile?.currentStreak ?? 0
                )
            }
            .sorted {
                if $0.focusMinutes != $1.focusMinutes {
                    return $0.focusMinutes > $1.focusMinutes
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

        if entries.isEmpty {
            errorMessage = "No members found for this group."
        }
    }

    private func fetchLatestGroupStreak(groupID: String) async -> Int? {
        guard let snapshot = try? await db.collection("groups").document(groupID).getDocument(),
              let data = snapshot.data()
        else { return nil }
        return data["currentGroupStreak"] as? Int ?? 0
    }
}
