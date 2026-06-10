//
//  UserService.swift
//  Screen time demo
//
//  Reads/writes for the `users` collection.
//

import FirebaseFirestore
import Foundation

final class UserService {
    static let shared = UserService()

    private let db = Firestore.firestore()

    private init() {}

    /// Placeholder names written before Apple/Firebase provided a real display name.
    private static let placeholderNames: Set<String> = ["", "User", "Member", "Studier"]

    /// Returns true if the string looks like an email (e.g. Apple's Hide My Email relay addresses).
    private static func looksLikeEmail(_ string: String) -> Bool {
        string.contains("@")
    }

    /// A stored name is replaceable if it is a known placeholder or an email-like string.
    private static func isReplaceable(_ name: String) -> Bool {
        placeholderNames.contains(name) || looksLikeEmail(name)
    }

    // MARK: - Display name

    /// Writes `displayName` to Firestore when the stored value is missing, a placeholder,
    /// or an email-like string (e.g. Apple's Hide My Email relay address).
    func syncDisplayName(uid: String, displayName: String) async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Don't store garbage — reject placeholders and email-like strings as the new value.
        guard !Self.placeholderNames.contains(trimmed), !Self.looksLikeEmail(trimmed) else { return }

        let ref = db.collection("users").document(uid)

        do {
            let snapshot = try await ref.getDocument()
            if snapshot.exists {
                let stored = snapshot.data()?["displayName"] as? String ?? ""
                guard Self.isReplaceable(stored) else { return }
                try await ref.updateData(["displayName": trimmed])
                print("[UserService] Updated displayName for \(uid) → \(trimmed)")
            } else {
                try await ref.setData([
                    "displayName": trimmed,
                    "photoURL": NSNull(),
                    "stats": [
                        "focusMinutes": 0,
                        "totalViolations": 0,
                        "currentStreak": 0,
                        "lastSessionDateStr": NSNull(),
                    ],
                ])
                print("[UserService] Created user doc for \(uid) → \(trimmed)")
            }
        } catch {
            print("[UserService] syncDisplayName failed for \(uid): \(error.localizedDescription)")
        }
    }

    /// Fetches display names via direct document reads (`users/{uid}`).
    func fetchDisplayNames(for uids: [String]) async -> [String: String] {
        guard !uids.isEmpty else { return [:] }

        var names: [String: String] = [:]

        await withTaskGroup(of: (String, String?).self) { group in
            for uid in uids {
                group.addTask {
                    (uid, try? await self.fetchDisplayName(uid: uid))
                }
            }

            for await (uid, name) in group {
                if let name, !Self.isReplaceable(name) {
                    names[uid] = name
                }
            }
        }

        return names
    }

    // MARK: - Profiles (Phase 5 leaderboard)

    /// Fetches full user profiles (name, stats) via direct document reads.
    func fetchProfiles(for uids: [String]) async -> [String: UserProfile] {
        guard !uids.isEmpty else { return [:] }

        var profiles: [String: UserProfile] = [:]

        await withTaskGroup(of: (String, UserProfile?).self) { group in
            for uid in uids {
                group.addTask {
                    let snapshot = try? await self.db.collection("users").document(uid).getDocument()
                    return (uid, snapshot.flatMap { UserProfile(document: $0) })
                }
            }

            for await (uid, profile) in group {
                if let profile {
                    profiles[uid] = profile
                }
            }
        }

        return profiles
    }

    private func fetchDisplayName(uid: String) async throws -> String? {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return data["displayName"] as? String
    }

    // MARK: - Push tokens (Phase 4)

    /// Appends a device FCM token to `users/{uid}.fcmTokens` (deduplicated by Firestore arrayUnion).
    func saveFCMToken(uid: String, token: String) async throws {
        let ref = db.collection("users").document(uid)
        let snapshot = try await ref.getDocument()

        if snapshot.exists {
            try await ref.updateData([
                "fcmTokens": FieldValue.arrayUnion([token]),
            ])
        } else {
            try await ref.setData([
                "fcmTokens": [token],
            ], merge: true)
        }

        print("[UserService] Saved FCM token for \(uid)")
    }
}
