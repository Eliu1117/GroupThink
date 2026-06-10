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

    // MARK: - Display name

    /// Writes `displayName` to Firestore when the stored value is missing or a placeholder.
    func syncDisplayName(uid: String, displayName: String) async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.placeholderNames.contains(trimmed) else { return }

        let ref = db.collection("users").document(uid)

        do {
            let snapshot = try await ref.getDocument()
            if snapshot.exists {
                let stored = snapshot.data()?["displayName"] as? String ?? ""
                guard Self.placeholderNames.contains(stored) else { return }
                try await ref.updateData(["displayName": trimmed])
                print("[UserService] Updated displayName for \(uid) → \(trimmed)")
            } else {
                try await ref.setData([
                    "displayName": trimmed,
                    "photoURL": NSNull(),
                    "stats": [
                        "focusMinutes": 0,
                        "currentStreak": 0,
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
                if let name, !Self.placeholderNames.contains(name) {
                    names[uid] = name
                }
            }
        }

        return names
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
