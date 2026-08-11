//
//  PersonalSessionSummary.swift
//  Screen time demo
//
//  Snapshot of a finished solo Home-page focus session, built locally the moment the
//  session ends. Mirrors `SessionSummary` but strips every multi-user/group concept —
//  there's no roster or leaderboard for a session only the local user participated in.
//

import Foundation

struct PersonalSessionSummary: Identifiable, Equatable {
    /// Session UUID — also used as sheet identity.
    let id: String
    let plannedDurationMin: Int
    let startAt: Date
    let endedAt: Date
    let wasStrictMode: Bool
    /// Whether the user stopped the block manually before the timer ran out.
    let endedEarly: Bool
    /// Times the user tapped through a shield to open (or tried to open) a blocked app,
    /// logged locally by the Shield/Monitor extensions via `SessionContextStore`.
    let openedBlockedAppCount: Int

    /// Minutes the session actually ran (may be less than planned if stopped early).
    var actualMinutes: Int {
        let elapsed = Int((endedAt.timeIntervalSince(startAt) / 60).rounded())
        return min(plannedDurationMin, max(elapsed, 0))
    }

    var stayedFocused: Bool {
        openedBlockedAppCount == 0 && !endedEarly
    }
}
