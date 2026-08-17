//
//  AppearanceSettings.swift
//  Screen time demo
//
//  Persists the user's light / dark / system appearance preference.
//

import Combine
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// `nil` tells SwiftUI to follow the device setting.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()

    private static let storageKey = "appearanceMode"

    @Published var mode: AppearanceMode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
            KawaiiAppearance.apply()
        }
    }

    var preferredColorScheme: ColorScheme? { mode.preferredColorScheme }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppearanceMode(rawValue: raw) {
            mode = stored
        } else {
            mode = .system
        }
    }
}
