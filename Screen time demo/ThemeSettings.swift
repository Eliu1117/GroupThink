//
//  ThemeSettings.swift
//  Screen time demo
//
//  Persists the user's selected color theme (AppTheme), independent of the separate
//  light/dark AppearanceMode preference. Mirrors AppearanceSettings' shape/pattern.
//

import Combine
import SwiftUI

@MainActor
final class ThemeSettings: ObservableObject {
    static let shared = ThemeSettings()

    private static let storageKey = "appTheme"

    /// The committed, persisted theme that every screen in the app renders with. Nothing
    /// outside this class should ever write to this directly — all edits flow through
    /// `previewTheme`/`commitPreview()` below so that merely *opening* Settings and tapping
    /// around swatches can never silently change what the rest of the app looks like.
    @Published private(set) var theme: AppTheme

    /// The theme actively being edited in the Settings screen. Swatch taps there only ever
    /// mutate this — never `theme` — so backing out of Settings (Done, swipe-to-dismiss, or
    /// just navigating away) without tapping "Apply" leaves the committed theme, and every
    /// already-on-screen color, completely untouched.
    @Published var previewTheme: AppTheme

    /// Whether a Settings session is currently editing `previewTheme`. While this is `true`,
    /// `Color.theme.*` resolves against `previewTheme` instead of `theme` (see `effectiveTheme`
    /// below), which is what makes swatch taps show up live in Settings' own cards/buttons/
    /// header. Call `beginPreview()`/`cancelPreview()`/`commitPreview()` to manage this rather
    /// than setting it directly.
    @Published private(set) var isPreviewing = false

    /// Bumped by `commitPreview()`. SwiftUI's live propagation of `Color.theme.*` changes to
    /// already-on-screen buttons/cards turned out to be unreliable in practice (only directly-
    /// reactive content consistently repainted). As a guaranteed fallback — mirroring how iOS
    /// briefly shows a "Setting Wallpaper…" transition rather than silently hoping every
    /// screen notices — `MainTabView` keys each tab's root content on this token, forcing a
    /// full, guaranteed-correct rebuild of every tab whenever a theme is actually applied.
    @Published private(set) var refreshToken = UUID()

    /// What `Color.theme.*` should resolve against right now: the in-progress edit while
    /// Settings is open and previewing, otherwise the real committed theme.
    var effectiveTheme: AppTheme { isPreviewing ? previewTheme : theme }

    /// Call when the Settings screen appears. Snapshots the committed theme into
    /// `previewTheme` so the picker starts in sync, then flips `Color.theme.*` over to
    /// resolving against that draft copy for the duration of the editing session.
    func beginPreview() {
        previewTheme = theme
        isPreviewing = true
    }

    /// Call when the Settings screen is dismissed without an explicit Apply (Done button,
    /// swipe-to-dismiss, or any other way of leaving). Simply stops resolving `Color.theme.*`
    /// against `previewTheme` — since `theme` itself was never touched, every screen snaps
    /// right back to whatever was committed before Settings was opened. Safe to call even if
    /// a preview was already committed/isn't active; it's a no-op in that case.
    func cancelPreview() {
        guard isPreviewing else { return }
        isPreviewing = false
    }

    /// Commits `previewTheme` as the real, persisted theme, applies it to UIKit-backed chrome,
    /// and forces every tab to fully rebuild with the new colors. Called by Settings' "Apply
    /// Everywhere" button only.
    func commitPreview() {
        theme = previewTheme
        UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
        KawaiiAppearance.apply()
        isPreviewing = false
        refreshToken = UUID()
    }

    private init() {
        let initial: AppTheme
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppTheme(rawValue: raw) {
            initial = stored
        } else {
            initial = .coffee
        }
        theme = initial
        previewTheme = initial
    }
}
