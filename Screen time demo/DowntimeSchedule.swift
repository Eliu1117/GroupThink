//
//  DowntimeSchedule.swift
//  Screen time demo
//
//  Per-user downtime schedule stored under `users/{uid}.downtime` in Firestore.
//  The allowed-apps selection is too large for Firestore and lives in App Group UserDefaults.
//

import Foundation

/// Represents a user's nightly downtime window.
struct DowntimeSchedule: Equatable {
    /// Whether this user has activated downtime for themselves.
    var enabled: Bool
    /// Hour the downtime window opens (0–23, local time).
    var startHour: Int
    var startMinute: Int
    /// Hour the downtime window closes (0–23, local time).
    var endHour: Int
    var endMinute: Int

    // MARK: - Defaults

    static let `default` = DowntimeSchedule(
        enabled: false,
        startHour: 22,
        startMinute: 0,
        endHour: 7,
        endMinute: 0
    )

    // MARK: - Firestore serialisation

    init(
        enabled: Bool,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int
    ) {
        self.enabled = enabled
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    init?(map: [String: Any]) {
        guard
            let startHour = map["startHour"] as? Int,
            let startMinute = map["startMinute"] as? Int,
            let endHour = map["endHour"] as? Int,
            let endMinute = map["endMinute"] as? Int
        else { return nil }

        self.enabled = map["enabled"] as? Bool ?? true
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
    }

    func asMap() -> [String: Any] {
        [
            "enabled": enabled,
            "startHour": startHour,
            "startMinute": startMinute,
            "endHour": endHour,
            "endMinute": endMinute,
        ]
    }

    // MARK: - Helpers

    /// `DateComponents` suitable for `DeviceActivitySchedule.intervalStart`.
    var startComponents: DateComponents {
        DateComponents(hour: startHour, minute: startMinute)
    }

    /// `DateComponents` suitable for `DeviceActivitySchedule.intervalEnd`.
    var endComponents: DateComponents {
        DateComponents(hour: endHour, minute: endMinute)
    }

    /// Formatted "10:00 PM" style string for display.
    func formattedStart() -> String {
        formatted(hour: startHour, minute: startMinute)
    }

    func formattedEnd() -> String {
        formatted(hour: endHour, minute: endMinute)
    }

    private func formatted(hour: Int, minute: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let date = Calendar.current.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Returns `true` if the current wall-clock time falls inside this downtime window.
    /// Handles overnight windows (e.g. 10 PM → 7 AM).
    func isCurrentlyActive(using calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let now = calendar.dateComponents([.hour, .minute], from: Date())
        guard let nowH = now.hour, let nowM = now.minute else { return false }

        let nowTotal = nowH * 60 + nowM
        let startTotal = startHour * 60 + startMinute
        let endTotal = endHour * 60 + endMinute

        if startTotal < endTotal {
            // Same-day window e.g. 14:00 – 17:00
            return nowTotal >= startTotal && nowTotal < endTotal
        } else {
            // Overnight window e.g. 22:00 – 07:00
            return nowTotal >= startTotal || nowTotal < endTotal
        }
    }
}
