//
//  SettingsView.swift
//  Screen time demo
//
//  Dedicated Settings screen: color theme picker (AppTheme) plus the existing
//  light/dark appearance control, moved here from ProfileView.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appearanceSettings: AppearanceSettings
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var navState: AppNavigationState
    @Environment(\.colorScheme) private var colorScheme

    /// Drives the brief "Applying theme…" full-screen transition — see `applyTheme()`.
    @State private var isApplyingTheme = false

    /// Everything in this screen reads/writes `themeSettings.previewTheme` (never `.theme`
    /// directly) via `beginPreview()`/`cancelPreview()`/`commitPreview()`, so swatch taps only
    /// ever edit a draft. If the sheet is dismissed any way other than "Apply Everywhere" —
    /// Done, swipe-to-dismiss, anything — `cancelPreview()` in `.onDisappear` discards the
    /// draft and every already-on-screen color snaps back to whatever was actually committed.
    @State private var isContentReady = false

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 100), spacing: 16)]

    var body: some View {
        ScrollView {
            if isContentReady {
                VStack(alignment: .leading, spacing: 28) {
                    themeSection
                    appearanceSection
                }
                .padding(24)
                .transition(.opacity)
            } else {
                settingsSkeleton
                    .padding(24)
            }
        }
        .kawaiiBackground()
        // Custom SwiftUI-native toolbar (title + Done) instead of relying on
        // `.navigationTitle`/UIKit's global `UINavigationBar.appearance()` chrome: that global
        // appearance proxy is only re-applied when a theme is actually *committed* (see
        // `KawaiiAppearance.apply()`), so it never reflected a swatch that was merely being
        // previewed — this is why the header used to look "stuck" on the last-applied theme
        // while the rest of the sheet updated live. Building it here with plain SwiftUI views
        // means it reads `Color.theme.*` on every render just like the rest of this screen.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(.theme.headline())
                    .foregroundStyle(Color.theme.text)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    navState.isSettingsPresented = false
                } label: {
                    Text("Done")
                        .font(.theme.body().weight(.bold))
                        .foregroundStyle(doneButtonColor)
                }
            }
        }
        .toolbarBackground(Color.theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .animation(.easeInOut(duration: 0.2), value: themeSettings.previewTheme)
        .fullScreenCover(isPresented: $isApplyingTheme) {
            ApplyingThemeView(theme: themeSettings.previewTheme)
        }
        .onAppear {
            themeSettings.beginPreview()
            // Let the sheet's own presentation transition complete and the real content
            // mount one runloop pass later, rather than racing both animations at once —
            // this (plus right-sizing the oversized theme PNGs — see `ThemeAssetPrefetcher`)
            // is what actually fixes the sheet feeling slow to appear. The skeleton below
            // covers that single pass so there's never a blank flash.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isContentReady = true
                }
            }
        }
        .onDisappear {
            themeSettings.cancelPreview()
            isContentReady = false
        }
    }

    /// Picking a swatch above only edits `themeSettings.previewTheme` (which this screen,
    /// and only this screen, is live-rendering against — see `ThemeSettings.effectiveTheme`).
    /// Tapping this button is the explicit "commit" step: it shows a brief, Apple-style
    /// "Applying…" transition — mirroring how iOS covers the screen while setting a new
    /// wallpaper — during which every tab's content is forced to fully rebuild with the new
    /// colors (see `ThemeSettings.commitPreview()`), then automatically dismisses Settings
    /// so the user lands straight back on a freshly-themed app rather than needing a second
    /// "Done" tap.
    /// `Color.theme.primary` already adapts between each theme's light/dark hex, but its dark
    /// variant (tuned for subtler fills/accents) reads as too muted for a bar button against
    /// the dark nav bar background. In dark mode, use the theme's *light* primary hex instead
    /// — still from whichever theme is currently previewed — so Done stays bright and clearly
    /// tappable instead of blending in.
    private var doneButtonColor: Color {
        guard colorScheme == .dark else { return Color.theme.primary }
        return Color(hex: themeSettings.previewTheme.palette.primaryLight)
    }

    private func applyTheme() {
        isApplyingTheme = true
        themeSettings.commitPreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            isApplyingTheme = false
            navState.isSettingsPresented = false
        }
    }

    // MARK: - Loading skeleton

    /// Lightweight placeholder shown for the single runloop pass between the sheet appearing
    /// and the real theme grid/cards mounting — see the `.onAppear` above.
    private var settingsSkeleton: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                skeletonBar(width: 120, height: 20)
                skeletonBar(width: 220, height: 14)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.theme.text.opacity(0.08))
                                .frame(width: 72, height: 72)
                            skeletonBar(width: 48, height: 10)
                        }
                    }
                }
                skeletonBar(width: nil, height: 44, cornerRadius: 22)
            }
            .kawaiiCard()

            VStack(alignment: .leading, spacing: 10) {
                skeletonBar(width: 110, height: 20)
                skeletonBar(width: nil, height: 32, cornerRadius: 8)
                skeletonBar(width: 200, height: 12)
            }
            .kawaiiCard()
        }
        .redacted(reason: .placeholder)
    }

    private func skeletonBar(width: CGFloat?, height: CGFloat, cornerRadius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.theme.text.opacity(0.08))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }

    // MARK: - Theme grid

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color Theme")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            Text("Choose the color palette for the whole app. Each theme still adapts to your light/dark setting below.")
                .font(.theme.caption())
                .foregroundStyle(Color.theme.text.opacity(0.55))

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(AppTheme.primaryGridThemes) { theme in
                    themeCell(theme)
                }
            }

            // Only surfaced once Boba is the active selection — keeps the grid uncluttered
            // and leaves room for other avatars/themes to someday get their own flavor
            // sub-pickers the same way, without stacking multiple rows at once.
            if themeSettings.previewTheme.isBobaFlavor {
                bobaFlavorPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            applyThemeButton
        }
        .animation(.snappy(duration: 0.2), value: themeSettings.previewTheme.isBobaFlavor)
        .kawaiiCard()
    }

    private var applyThemeButton: some View {
        Button {
            applyTheme()
        } label: {
            Label("Apply \(themeSettings.previewTheme.displayName) Everywhere", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.kawaiiPrimary())
        .padding(.top, 6)
    }

    /// Boba is represented by a single grid cell above (always showing as whichever Boba
    /// flavor is currently active, defaulting to Classic). This lets the user swap that
    /// cell's underlying color scheme to Taro or Matcha without the grid growing three
    /// separate "boba" entries.
    private var bobaFlavorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Boba Color")
                .font(.theme.caption().weight(.semibold))
                .foregroundStyle(Color.theme.text.opacity(0.7))

            HStack(spacing: 14) {
                ForEach(AppTheme.bobaFlavors) { flavor in
                    bobaFlavorSwatch(flavor)
                }
            }
        }
        .padding(.top, 4)
    }

    private func bobaFlavorSwatch(_ flavor: AppTheme) -> some View {
        let isSelected = themeSettings.previewTheme == flavor

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                themeSettings.previewTheme = flavor
            }
        } label: {
            VStack(spacing: 4) {
                Image(flavor.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(width: 44, height: 44)
                    .background(Color.theme.secondary.opacity(0.18))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            isSelected ? Color.theme.primary : Color.theme.text.opacity(0.15),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                    )

                Text(flavor.bobaFlavorLabel)
                    .font(.theme.caption(10))
                    .foregroundStyle(Color.theme.text.opacity(isSelected ? 0.9 : 0.5))
            }
        }
        .buttonStyle(.plain)
    }

    /// The current Boba-family theme if one is selected (so the main grid cell can reflect
    /// Taro/Matcha art once chosen), falling back to Classic when no Boba flavor is active.
    private var activeBobaFlavor: AppTheme {
        themeSettings.previewTheme.isBobaFlavor ? themeSettings.previewTheme : .classicBoba
    }

    private func themeCell(_ theme: AppTheme) -> some View {
        // The Boba grid cell always represents whichever flavor is currently active, so its
        // art/label/selection state track `activeBobaFlavor` rather than the static
        // `.classicBoba` case passed in from `primaryGridThemes`.
        let displayTheme = theme == .classicBoba ? activeBobaFlavor : theme
        let isSelected = theme == .classicBoba ? themeSettings.previewTheme.isBobaFlavor : themeSettings.previewTheme == theme

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                themeSettings.previewTheme = theme == .classicBoba ? activeBobaFlavor : theme
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(displayTheme.assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                        .frame(width: 72, height: 72)
                        .background(Color.theme.secondary.opacity(0.18))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                isSelected ? Color.theme.primary : Color.theme.text.opacity(0.15),
                                lineWidth: isSelected ? 3 : 1.5
                            )
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                        .scaleEffect(isSelected ? 1.06 : 1.0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.theme.primary)
                            .background(Color.theme.surface, in: Circle())
                            .offset(x: 3, y: 3)
                    }
                }

                Text(theme == .classicBoba ? "Boba" : displayTheme.displayName)
                    .font(.theme.caption(11))
                    .foregroundStyle(Color.theme.text.opacity(isSelected ? 0.9 : 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Appearance (light/dark)

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            Picker("Appearance", selection: $appearanceSettings.mode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Auto follows your iPhone’s light or dark mode setting.")
                .font(.theme.caption())
                .foregroundStyle(Color.theme.text.opacity(0.55))
        }
        .kawaiiCard()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AppearanceSettings.shared)
    .environmentObject(ThemeSettings.shared)
    .environmentObject(AppNavigationState.shared)
}
