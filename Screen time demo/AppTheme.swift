//
//  AppTheme.swift
//  Screen time demo
//
//  The selectable color themes, matching the "cute drink character" artwork in
//  Assets.xcassets so theme and avatar identity feel like the same design language.
//  Each theme defines its own light + dark variant for every semantic color used by
//  Theme.swift's `Color.theme` namespace — independent of the user's light/dark
//  AppearanceMode, which only decides which of the two variants is shown.
//

import Foundation

/// One semantic color palette, with a light and dark hex value for each role.
/// Mirrors the roles originally hardcoded in `Color.theme` (Theme.swift).
struct ThemePalette {
    let primaryLight: String
    let primaryDark: String
    let secondaryLight: String
    let secondaryDark: String
    let backgroundLight: String
    let backgroundDark: String
    let textLight: String
    let textDark: String
    let surfaceLight: String
    let surfaceDark: String
    let accentLight: String
    let accentDark: String
}

enum AppTheme: String, CaseIterable, Identifiable {
    case coffee
    /// Purple/taro palette — renders with the dedicated "taro-boba" character art.
    case boba
    case energyDrink = "energy drink"
    case milk
    case water
    /// Green/lime palette — split off from `energyDrink`, which moved to a neon-orange base.
    /// Renders with the dedicated "matcha-boba" character art.
    case matcha
    /// Classic milk-tea boba — caramel/tan palette, reusing the original plain "boba" cup art
    /// (now that `.boba` itself has moved to the purple-tinted "taro-boba" artwork).
    case classicBoba = "classic boba"

    var id: String { rawValue }

    /// Exact Assets.xcassets imageset name for this theme's swatch icon.
    var assetName: String {
        switch self {
        case .coffee: return "coffee"
        case .boba: return "taro-boba"
        case .energyDrink: return "energy drink"
        // Displays as "Strawberry Milk" below — use the dedicated strawberry-tinted art
        // (added alongside the avatar skins) rather than the generic "milk" asset, which
        // isn't necessarily strawberry-colored itself.
        case .milk: return "strawberry-milk"
        case .water: return "water"
        case .matcha: return "matcha-boba"
        case .classicBoba: return "boba"
        }
    }

    var displayName: String {
        switch self {
        case .coffee: return "Velvet Brew"
        case .boba: return "Taro Boba"
        case .energyDrink: return "Neon Zest"
        case .milk: return "Strawberry Milk"
        case .water: return "Still Water"
        case .matcha: return "Matcha Boba"
        case .classicBoba: return "Classic Boba"
        }
    }

    static func random() -> AppTheme {
        allCases.randomElement() ?? .coffee
    }

    /// Themes that each get their own cell in the Settings color-theme grid. `.boba` and
    /// `.matcha` are deliberately excluded here — they're "flavors" of the single Boba
    /// family, surfaced instead via `bobaFlavors`/the Boba flavor sub-picker, with
    /// `.classicBoba` standing in as the one visible, primary Boba grid cell.
    static var primaryGridThemes: [AppTheme] {
        [.classicBoba, .coffee, .energyDrink, .milk, .water]
    }

    /// The Boba family's color-scheme variants, in display order — Classic first since it's
    /// the default/main look.
    static var bobaFlavors: [AppTheme] {
        [.classicBoba, .boba, .matcha]
    }

    /// Whether this theme is one of the Boba family's color-scheme variants.
    var isBobaFlavor: Bool { AppTheme.bobaFlavors.contains(self) }

    /// Short flavor name used in the Boba sub-picker (vs. the full `displayName`).
    var bobaFlavorLabel: String {
        switch self {
        case .classicBoba: return "Classic"
        case .boba: return "Taro"
        case .matcha: return "Matcha"
        default: return displayName
        }
    }

    var palette: ThemePalette {
        switch self {
        case .coffee:
            // Original "Velvet Brew" palette — kept as the app's default theme.
            return ThemePalette(
                primaryLight: "FADADD", primaryDark: "9E6B78",
                secondaryLight: "D0E8D0", secondaryDark: "5A7A5A",
                backgroundLight: "FDF5E6", backgroundDark: "2A2118",
                textLight: "6F4E37", textDark: "F0E4D4",
                surfaceLight: "FFFFFF", surfaceDark: "3A2F26",
                accentLight: "2F5A40", accentDark: "6B9B7A"
            )
        case .boba:
            // Taro purple + tapioca tan.
            return ThemePalette(
                primaryLight: "D7B9E8", primaryDark: "7A5A94",
                secondaryLight: "F6DFC2", secondaryDark: "8C6F4E",
                backgroundLight: "F7F0FB", backgroundDark: "231A2B",
                textLight: "4A2E52", textDark: "EDE0F5",
                surfaceLight: "FFFFFF", surfaceDark: "362A40",
                accentLight: "6B3FA0", accentDark: "A685C9"
            )
        case .energyDrink:
            // Neon orange base.
            return ThemePalette(
                primaryLight: "FFB347", primaryDark: "CC6A1E",
                secondaryLight: "FFE0B2", secondaryDark: "8C5A2E",
                backgroundLight: "FFF6EC", backgroundDark: "241509",
                textLight: "6B3410", textDark: "FBE3CC",
                surfaceLight: "FFFFFF", surfaceDark: "3A2615",
                accentLight: "FF6A00", accentDark: "FF9D4D"
            )
        case .matcha:
            // Soft matcha lime + cyan — the original "energy drink" palette, now its own theme.
            return ThemePalette(
                primaryLight: "B6F09C", primaryDark: "3F7D3A",
                secondaryLight: "A0E7E5", secondaryDark: "2E6B6B",
                backgroundLight: "F0FAEC", backgroundDark: "101D14",
                textLight: "1F4D2E", textDark: "E3F7E8",
                surfaceLight: "FFFFFF", surfaceDark: "1C2E20",
                accentLight: "2E9E4F", accentDark: "6ED98A"
            )
        case .milk:
            // Strawberry milk pink + cream (lighter / softer than coffee's).
            return ThemePalette(
                primaryLight: "FFD3E0", primaryDark: "B06B82",
                secondaryLight: "FFF1D6", secondaryDark: "8C7A52",
                backgroundLight: "FFF8FA", backgroundDark: "2A1F23",
                textLight: "7A3B52", textDark: "F5E0E8",
                surfaceLight: "FFFFFF", surfaceDark: "3A2A30",
                accentLight: "C6456F", accentDark: "E88AA8"
            )
        case .water:
            // Aqua blue + seafoam.
            return ThemePalette(
                primaryLight: "C5E8F5", primaryDark: "3D6B82",
                secondaryLight: "D9F0E8", secondaryDark: "4E7A6B",
                backgroundLight: "F0FAFD", backgroundDark: "141F26",
                textLight: "1F4A5C", textDark: "E0F0F7",
                surfaceLight: "FFFFFF", surfaceDark: "23323A",
                accentLight: "2D7A9E", accentDark: "6EC0E0"
            )
        case .classicBoba:
            // Caramel milk tea + cream, with dark tapioca-pearl brown as the accent.
            return ThemePalette(
                primaryLight: "E8C9A0", primaryDark: "9C7347",
                secondaryLight: "F5E6D3", secondaryDark: "7A5C3E",
                backgroundLight: "FFF9F0", backgroundDark: "211509",
                textLight: "5C3A1E", textDark: "F2E0C8",
                surfaceLight: "FFFFFF", surfaceDark: "332112",
                accentLight: "6B3F1D", accentDark: "C9956A"
            )
        }
    }
}
