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
    /// advances the individual streak, then attempts the group streak update.
    /// Safe to call multiple times for the same session — only the first call wins.
    func recordSessionCompletion(
        groupID: String,
        sessionID: String,
        userUID: String,
        focusMinutes: Int
    ) async {
        guard focusMinutes > 0 else { return }
        guard markAwarded(sessionID: sessionID) else {
            print("[Stats] Session \(sessionID) already awarded — skipping")
            return
        }

        do {
            try await updateUserStats(userUID: userUID, focusMinutes: focusMinutes)
            print("[Stats] Awarded \(focusMinutes) focus min to \(userUID) for session \(sessionID)")
        } catch {
            // Allow a retry on the next session-end signal.
            unmarkAwarded(sessionID: sessionID)
            print("[Stats] Failed to award user stats: \(error.localizedDescription)")
            return
        }

        await updateGroupStreakIfEarned(groupID: groupID)
    }

    // MARK: - Individual stats (focus minutes + streak)

    /// Transactionally increments `stats.focusMinutes`, advances `stats.currentStreak`
    /// based on `stats.lastSessionDate`, and stamps today as the last session day.
    private func updateUserStats(userUID: String, focusMinutes: Int) async throws {
        let ref = db.collection("users").document(userUID)

        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            let stats = snapshot.data()?["stats"] as? [String: Any]
            let currentMinutes = stats?["focusMinutes"] as? Int ?? 0
            let currentStreak = stats?["currentStreak"] as? Int ?? 0
            let lastSessionDate = (stats?["lastSessionDate"] as? Timestamp)?.dateValue()

            let now = Date()
            let newStreak = Self.nextStreak(current: currentStreak, lastDate: lastSessionDate, now: now)

            transaction.setData(
                [
                    "stats": [
                        "focusMinutes": currentMinutes + focusMinutes,
                        "currentStreak": newStreak,
                        "lastSessionDate": Timestamp(date: now),
                    ],
                ],
                forDocument: ref,
                merge: true
            )
            return nil
        }
    }

    /// Streak rules: same day → unchanged, yesterday → +1, gap or first session → reset to 1.
    static func nextStreak(
        current: Int,
        lastDate: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard let lastDate else { return 1 }

        if calendar.isDate(lastDate, inSameDayAs: now) {
            return max(current, 1)
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(lastDate, inSameDayAs: yesterday) {
            return current + 1
        }

        return 1
    }

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

            if let lastUpdate = (data["lastGroupStreakUpdate"] as? Timestamp)?.dateValue(),
               calendar.isDate(lastUpdate, inSameDayAs: now) {
                return // Already counted today.
            }

            guard await allMembersStudiedToday(memberUids, calendar: calendar, now: now) else {
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
                let lastUpdate = (data?["lastGroupStreakUpdate"] as? Timestamp)?.dateValue()

                // Re-check inside the transaction: another member may have just counted today.
                if let lastUpdate, calendar.isDate(lastUpdate, inSameDayAs: now) {
                    return nil
                }

                let currentStreak = data?["currentGroupStreak"] as? Int ?? 0
                let newStreak = Self.nextStreak(current: currentStreak, lastDate: lastUpdate, now: now, calendar: calendar)

                transaction.updateData(
                    [
                        "currentGroupStreak": newStreak,
                        "lastGroupStreakUpdate": Timestamp(date: now),
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

    private func allMembersStudiedToday(
        _ memberUids: [String],
        calendar: Calendar,
        now: Date
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            for uid in memberUids {
                group.addTask {
                    guard let snapshot = try? await self.db.collection("users").document(uid).getDocument(),
                          let stats = snapshot.data()?["stats"] as? [String: Any],
                          let last = (stats["lastSessionDate"] as? Timestamp)?.dateValue()
                    else { return false }
                    return calendar.isDate(last, inSameDayAs: now)
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
