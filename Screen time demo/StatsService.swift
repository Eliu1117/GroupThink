//
//  StatsService.swift
//  Screen time demo
//
//  Phase 5 — Stats & Retention.
//
//  Awards focus minutes and maintains individual/group streaks when a study
//  session ends. Because Firestore rules only allow a user to write their own
//  `users/{uid}` doc, every device awards stats for ITS OWN user when it
//  observes the session end; the group streak is then updated by whichever
//  member finishes the check first (the write is idempotent per calendar day).
//

import FirebaseFirestore
import Foundation

final class StatsService {
    static let shared = StatsService()

    private let db = Firestore.firestore()
    private let defaults = UserDefaults.standard

    /// Session IDs already awarded on this device (idempotency guard).
    private static let awardedSessionsKey = "stats.awardedSessionIDs"
    private static let maxRememberedSessions = 20

    private init() {}

    // MARK: - Public entry point

    /// Records a completed session for the local user: increments focus minutes,
    /// logs violations, advances the individual streak, then attempts the group streak update.
    /// Safe to call multiple times for the same session — only the first call wins.
    func recordSessionCompletion(
        groupID: String,
        sessionID: String,
        userUID: String,
        focusMinutes: Int,
        violated: Bool = false
    ) async {
        guard focusMinutes > 0 || violated else { return }
        guard markAwarded(sessionID: sessionID) else {
            print("[Stats] Session \(sessionID) already awarded — skipping")
            return
        }

        do {
            try await updateUserStats(userUID: userUID, durationMinutes: focusMinutes, violated: violated)
            print("[Stats] Awarded \(focusMinutes)min / violated=\(violated) to \(userUID) for session \(sessionID)")
        } catch {
            // Allow a retry on the next session-end signal.
            unmarkAwarded(sessionID: sessionID)
            print("[Stats] Failed to award user stats: \(error.localizedDescription)")
            return
        }

        await updateGroupStreakIfEarned(groupID: groupID)
    }

    // MARK: - Individual stats (focus minutes + streak)

    /// Atomically increments `stats.focusMinutes` and (if violated) `stats.totalViolations`
    /// using `FieldValue.increment` — no document read required.
    /// Streak update requires a read and runs in a separate transaction.
    func updateUserStats(userUID: String, durationMinutes: Int, violated: Bool) async throws {
        let ref = db.collection("users").document(userUID)

        // Blind atomic increments — write without reading.
        var increments: [String: Any] = [:]
        if durationMinutes > 0 {
            increments["stats.focusMinutes"] = FieldValue.increment(Int64(durationMinutes))
        }
        if violated {
            increments["stats.totalViolations"] = FieldValue.increment(Int64(1))
        }
        if !increments.isEmpty {
            try await ref.setData(increments, merge: true)
        }

        // Streak advance requires knowing last session's date — transaction read is necessary.
        try await updateStreakIfNeeded(ref: ref)
    }

    /// Reads `stats.lastSessionDateStr`, computes the new streak, and writes both
    /// the streak and today's date string back atomically.
    private func updateStreakIfNeeded(ref: DocumentReference) async throws {
        let todayStr = Self.dateString(from: Date())

        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            let stats = snapshot.data()?["stats"] as? [String: Any]
            let currentStreak = stats?["currentStreak"] as? Int ?? 0
            let lastDateStr = stats?["lastSessionDateStr"] as? String

            let newStreak = Self.nextStreakByDateString(
                current: currentStreak,
                lastDateStr: lastDateStr,
                todayStr: todayStr
            )

            transaction.setData(
                ["stats": ["currentStreak": newStreak, "lastSessionDateStr": todayStr]],
                forDocument: ref,
                merge: true
            )
            return nil
        }
    }

    // MARK: - Streak helpers

    /// Computes the next streak value using `yyyy-MM-dd` string comparison.
    /// - Same day → keep (idempotent).
    /// - Yesterday → increment.
    /// - Gap or first session → reset to 1.
    static func nextStreakByDateString(
        current: Int,
        lastDateStr: String?,
        todayStr: String
    ) -> Int {
        guard let lastDateStr else { return 1 }
        if lastDateStr == todayStr { return max(current, 1) }

        let formatter = Self.dateFormatter
        guard
            let today = formatter.date(from: todayStr),
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)
        else { return 1 }

        return formatter.string(from: yesterday) == lastDateStr ? current + 1 : 1
    }

    static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Group streak

    /// The group streak survives a day only if EVERY member completed at least one
    /// session that calendar day. Checked client-side after the local user's stats
    /// are written; the final write is guarded by a transaction so concurrent
    /// members can't double-count the same day.
    private func updateGroupStreakIfEarned(groupID: String) async {
        let groupRef = db.collection("groups").document(groupID)
        let calendar = Calendar.current
        let now = Date()

        do {
            let groupSnapshot = try await groupRef.getDocument()
            guard let data = groupSnapshot.data(),
                  let memberUids = data["memberUids"] as? [String],
                  !memberUids.isEmpty
            else { return }

            if let lastUpdateStr = data["lastGroupStreakUpdateStr"] as? String,
               lastUpdateStr == Self.dateString(from: now) {
                return // Already counted today.
            }

            guard await allMembersStudiedToday(memberUids, now: now) else {
                print("[Stats] Group \(groupID): not all members studied today — streak unchanged")
                return
            }

            _ = try await db.runTransaction { transaction, errorPointer in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(groupRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                let data = snapshot.data()
                let lastUpdateStr = data?["lastGroupStreakUpdateStr"] as? String
                let todayStr = Self.dateString(from: now)

                // Re-check inside the transaction: another member may have just counted today.
                if lastUpdateStr == todayStr {
                    return nil
                }

                let currentStreak = data?["currentGroupStreak"] as? Int ?? 0
                let newStreak = Self.nextStreakByDateString(
                    current: currentStreak,
                    lastDateStr: lastUpdateStr,
                    todayStr: todayStr
                )

                transaction.updateData(
                    [
                        "currentGroupStreak": newStreak,
                        "lastGroupStreakUpdateStr": todayStr,
                    ],
                    forDocument: groupRef
                )
                return nil
            }

            print("[Stats] Group \(groupID): group streak advanced")
        } catch {
            print("[Stats] Group streak update failed: \(error.localizedDescription)")
        }
    }

    private func allMembersStudiedToday(_ memberUids: [String], now: Date) async -> Bool {
        let todayStr = Self.dateString(from: now)
        return await withTaskGroup(of: Bool.self) { group in
            for uid in memberUids {
                group.addTask {
                    guard let snapshot = try? await self.db.collection("users").document(uid).getDocument(),
                          let stats = snapshot.data()?["stats"] as? [String: Any],
                          let lastStr = stats["lastSessionDateStr"] as? String
                    else { return false }
                    return lastStr == todayStr
                }
            }

            for await studiedToday in group {
                if !studiedToday {
                    group.cancelAll()
                    return false
                }
            }
            return true
        }
    }  

    // MARK: - Idempotency

    /// Returns `true` if this session had not been awarded yet (and marks it now).
    private func markAwarded(sessionID: String) -> Bool {
        var awarded = defaults.stringArray(forKey: Self.awardedSessionsKey) ?? []
        guard !awarded.contains(sessionID) else { return false }

        awarded.append(sessionID)
        if awarded.count > Self.maxRememberedSessions {
            awarded.removeFirst(awarded.count - Self.maxRememberedSessions)
        }
        defaults.set(awarded, forKey: Self.awardedSessionsKey)
        return true
    }

    private func unmarkAwarded(sessionID: String) {
        var awarded = defaults.stringArray(forKey: Self.awardedSessionsKey) ?? []
        awarded.removeAll { $0 == sessionID }
        defaults.set(awarded, forKey: Self.awardedSessionsKey)
    }
}
