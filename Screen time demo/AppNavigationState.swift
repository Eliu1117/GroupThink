//
//  AppNavigationState.swift
//  Screen time demo
//
//  Tiny app-wide presentation store, used so Settings can be presented as a sheet attached
//  to `MainTabView` itself (outside any individual tab's own navigation/view identity).
//  That matters for "Apply Theme" (see `ThemeSettings.refreshToken`): applying a theme
//  forces each TAB's root content to fully rebuild (guaranteeing every button/card actually
//  repaints), but since the Settings sheet lives one level up, above that reset, it's
//  completely unaffected — the user stays right where they were throughout.
//

import Combine
import Foundation

@MainActor
final class AppNavigationState: ObservableObject {
    static let shared = AppNavigationState()

    @Published var isSettingsPresented = false

    private init() {}
}
