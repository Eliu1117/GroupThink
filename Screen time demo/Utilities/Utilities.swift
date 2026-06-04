//
//  Utilities.swift
//  Screen time demo
//
//  Small shared helpers.
//

import Foundation

extension Array {
    /// Splits the array into chunks of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// Produces stable `yyyy-MM-dd` day keys in the user's current calendar, used for streaks.
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    static func today() -> String {
        key(for: Date())
    }

    static func yesterday() -> String {
        key(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }
}
