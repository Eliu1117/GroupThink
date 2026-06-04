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
    private var users: CollectionReference { db.collection("users") }

    private init() {}

    /// Creates the user document on first sign-in, or updates the display name/photo
    /// if it already exists. Stats are preserved across sign-ins.
    func upsertUser(uid: String, displayName: String, photoURL: String?) async throws {
        let ref = users.document(uid)
        let snapshot = try await ref.getDocument()

        if snapshot.exists {
            var data: [String: Any] = ["displayName": displayName]
            if let photoURL { data["photoURL"] = photoURL }
            try await ref.updateData(data)
        } else {
            let user = AppUser(id: uid, displayName: displayName, photoURL: photoURL)
            try ref.setData(from: user)
        }
    }

    func fetchUser(uid: String) async throws -> AppUser {
        try await users.document(uid).getDocument(as: AppUser.self)
    }

    func fetchUsers(uids: [String]) async throws -> [AppUser] {
        guard !uids.isEmpty else { return [] }
        // Firestore `in` queries are limited to 10 values; chunk to be safe.
        var result: [AppUser] = []
        for chunk in uids.chunked(into: 10) {
            let snapshot = try await users
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            result += snapshot.documents.compactMap { try? $0.data(as: AppUser.self) }
        }
        return result
    }

    func observeUser(uid: String, onChange: @escaping (AppUser?) -> Void) -> ListenerRegistration {
        users.document(uid).addSnapshotListener { snapshot, _ in
            onChange(try? snapshot?.data(as: AppUser.self))
        }
    }

    func addFCMToken(uid: String, token: String) async throws {
        try await users.document(uid).updateData([
            "fcmTokens": FieldValue.arrayUnion([token])
        ])
    }

    func removeFCMToken(uid: String, token: String) async throws {
        try await users.document(uid).updateData([
            "fcmTokens": FieldValue.arrayRemove([token])
        ])
    }

    /// Adds focus minutes and updates the daily streak when a session completes.
    func recordCompletedSession(uid: String, focusMinutes: Int) async throws {
        let ref = users.document(uid)
        let today = DayKey.today()
        let yesterday = DayKey.yesterday()

        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let stats = (snapshot.data()?["stats"] as? [String: Any]) ?? [:]
            let lastDay = stats["lastSessionDay"] as? String
            let currentStreak = stats["currentStreak"] as? Int ?? 0

            let newStreak: Int
            if lastDay == today {
                newStreak = max(currentStreak, 1)
            } else if lastDay == yesterday {
                newStreak = currentStreak + 1
            } else {
                newStreak = 1
            }

            transaction.updateData([
                "stats.focusMinutes": FieldValue.increment(Int64(focusMinutes)),
                "stats.currentStreak": newStreak,
                "stats.lastSessionDay": today
            ], forDocument: ref)
            return nil
        }
    }
}
