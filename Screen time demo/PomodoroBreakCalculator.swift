//
//  PomodoroBreakCalculator.swift
//  Screen time demo
//
//  GRO-40: break-length math for back-to-back (Pomodoro-style) session cycles.
//  Pure/static so the rules are easy to reason about and test independently of
//  SessionViewModel's Firestore/timer plumbing.
//

import Foundation

/// Host-configured break rules for a Pomodoro cycle, snapshotted onto the session doc.
struct PomodoroConfiguration: Equatable {
    var standardBreakMin: Int
    var longBreakEnabled: Bool
    var longBreakEveryN: Int
    var longBreakMin: Int

    static let defaultSessionCount = 2
    static let defaultStandardBreakMin = 5
    static let defaultLongBreakEveryN = 4
    static let defaultLongBreakMin = 15

    static var defaults: PomodoroConfiguration {
        PomodoroConfiguration(
            standardBreakMin: defaultStandardBreakMin,
            longBreakEnabled: false,
            longBreakEveryN: defaultLongBreakEveryN,
            longBreakMin: defaultLongBreakMin
        )
    }

    var firestoreFields: [String: Any] {
        [
            "pomodoroBreakMin": max(1, standardBreakMin),
            "pomodoroLongBreakEveryN": longBreakEnabled ? max(2, longBreakEveryN) : 0,
            "pomodoroLongBreakMin": max(1, longBreakMin),
        ]
    }

    static func from(sessionData data: [String: Any], sessionDurationMin: Int) -> PomodoroConfiguration {
        if let breakMin = data["pomodoroBreakMin"] as? Int {
            let everyN = data["pomodoroLongBreakEveryN"] as? Int ?? 0
            let longMin = data["pomodoroLongBreakMin"] as? Int ?? defaultLongBreakMin
            return PomodoroConfiguration(
                standardBreakMin: breakMin,
                longBreakEnabled: everyN > 0,
                longBreakEveryN: everyN > 0 ? everyN : defaultLongBreakEveryN,
                longBreakMin: longMin
            )
        }
        return legacy(forSessionDurationMin: sessionDurationMin)
    }

    /// Pre-customization sessions: scale standard breaks with session length; every 4th is long.
    static func legacy(forSessionDurationMin durationMin: Int) -> PomodoroConfiguration {
        let standard = max(1, Int((Double(durationMin) * 0.2).rounded()))
        let long = max(standard + 1, Int((Double(standard) * 3.5).rounded()))
        return PomodoroConfiguration(
            standardBreakMin: standard,
            longBreakEnabled: true,
            longBreakEveryN: 4,
            longBreakMin: long
        )
    }
}

enum PomodoroBreakCalculator {
    static func isLongBreak(afterSessionIndex sessionIndex: Int, configuration: PomodoroConfiguration) -> Bool {
        configuration.longBreakEnabled
            && configuration.longBreakEveryN > 0
            && sessionIndex % configuration.longBreakEveryN == 0
    }

    static func breakSeconds(afterSessionIndex sessionIndex: Int, configuration: PomodoroConfiguration) -> Int {
        if isLongBreak(afterSessionIndex: sessionIndex, configuration: configuration) {
            return max(1, configuration.longBreakMin) * 60
        }
        return max(1, configuration.standardBreakMin) * 60
    }
}
