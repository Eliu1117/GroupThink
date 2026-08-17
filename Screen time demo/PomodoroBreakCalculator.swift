//
//  PomodoroBreakCalculator.swift
//  Screen time demo
//
//  GRO-40: break-length math for back-to-back (Pomodoro-style) session cycles.
//  Pure/static so the rules are easy to reason about and test independently of
//  SessionViewModel's Firestore/timer plumbing.
//

import Foundation

enum PomodoroBreakCalculator {
    /// Standard breaks are this fraction of the sub-session length (min 1 minute).
    private static let standardBreakRatio = 0.2
    /// Long breaks (every 4th) are this many times longer than a standard break.
    private static let longBreakMultiplier = 3.5
    /// Every Nth break is a long break, mirroring the classic Pomodoro technique.
    private static let longBreakInterval = 4

    /// True when the break following `sessionIndex` (1-based) should be a long break.
    static func isLongBreak(afterSessionIndex sessionIndex: Int) -> Bool {
        sessionIndex % longBreakInterval == 0
    }

    /// Seconds the break following sub-session `sessionIndex` should last, given that
    /// sub-session's planned length in minutes. Standard breaks scale with the session
    /// length (longer focus sessions earn longer breaks); every 4th break is long.
    static func breakSeconds(afterSessionIndex sessionIndex: Int, sessionDurationMin: Int) -> Int {
        let standardMinutes = max(1, Int((Double(sessionDurationMin) * standardBreakRatio).rounded()))
        guard isLongBreak(afterSessionIndex: sessionIndex) else {
            return standardMinutes * 60
        }
        let longMinutes = max(standardMinutes + 1, Int((Double(standardMinutes) * longBreakMultiplier).rounded()))
        return longMinutes * 60
    }
}
