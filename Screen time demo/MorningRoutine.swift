//
//  MorningRoutine.swift  (GRO-32: type renamed to Routine; file name kept for Xcode project compat)
//  Screen time demo
//
//  Per-user routine stored under `users/{uid}.morningRoutine` in Firestore.
//  The Firestore map key "morningRoutine" is intentionally preserved for backward compatibility.
//  Routine apps (the allowed-activity selection) are cached in App Group UserDefaults
//  because FamilyActivitySelection tokens cannot be serialised to Firestore.
//

import Foundation

/// Determines when routine blocking is lifted.
enum RoutineUnlockMode: String, CaseIterable {
    /// Shields drop automatically at `unlockHour:unlockMinute`.
    case timeBased = "timeBased"
    /// Shields drop once the user accumulates `unlockActivityMinutes` inside
    /// approved routine apps, detected via a DeviceActivityEvent threshold.
    case activityBased = "activityBased"

    var label: String {
        switch self {
        case .timeBased: return "Time-based"
        case .activityBased: return "Activity-based"
        }
    }
}

struct Routine: Equatable {
    var enabled: Bool
    /// Hour the routine block begins.
    var lockHour: Int
    var lockMinute: Int
    /// For `timeBased`: apps unlock at this hour/minute.
    var unlockHour: Int
    var unlockMinute: Int
    var unlockMode: RoutineUnlockMode
    /// For `activityBased`: how many minutes in routine apps are required.
    var unlockActivityMinutes: Int

    // MARK: - Defaults

    static let `default` = Routine(
        enabled: false,
        lockHour: 6,
        lockMinute: 0,
        unlockHour: 8,
        unlockMinute: 0,
        unlockMode: .timeBased,
        unlockActivityMinutes: 10
    )

    // MARK: - Firestore serialisation

    init(
        enabled: Bool,
        lockHour: Int,
        lockMinute: Int,
        unlockHour: Int,
        unlockMinute: Int,
        unlockMode: RoutineUnlockMode,
        unlockActivityMinutes: Int
    ) {
        self.enabled = enabled
        self.lockHour = lockHour
        self.lockMinute = lockMinute
        self.unlockHour = unlockHour
        self.unlockMinute = unlockMinute
        self.unlockMode = unlockMode
        self.unlockActivityMinutes = unlockActivityMinutes
    }

    init?(map: [String: Any]) {
        guard
            let lockHour = map["lockHour"] as? Int,
            let lockMinute = map["lockMinute"] as? Int,
            let unlockHour = map["unlockHour"] as? Int,
            let unlockMinute = map["unlockMinute"] as? Int
        else { return nil }

        self.enabled = map["enabled"] as? Bool ?? true
        self.lockHour = lockHour
        self.lockMinute = lockMinute
        self.unlockHour = unlockHour
        self.unlockMinute = unlockMinute
        self.unlockMode = RoutineUnlockMode(rawValue: map["unlockMode"] as? String ?? "") ?? .timeBased
        self.unlockActivityMinutes = map["unlockActivityMinutes"] as? Int ?? 10
    }

    func asMap() -> [String: Any] {
        [
            "enabled": enabled,
            "lockHour": lockHour,
            "lockMinute": lockMinute,
            "unlockHour": unlockHour,
            "unlockMinute": unlockMinute,
            "unlockMode": unlockMode.rawValue,
            "unlockActivityMinutes": unlockActivityMinutes,
        ]
    }

    // MARK: - Helpers

    var lockComponents: DateComponents { DateComponents(hour: lockHour, minute: lockMinute) }
    var unlockComponents: DateComponents { DateComponents(hour: unlockHour, minute: unlockMinute) }

    func formattedLockTime() -> String { formatted(hour: lockHour, minute: lockMinute) }
    func formattedUnlockTime() -> String { formatted(hour: unlockHour, minute: unlockMinute) }

    private func formatted(hour: Int, minute: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let date = Calendar.current.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
