//
//  AvatarOption.swift
//  Screen time demo
//
//  The 5 built-in "cute drink character" avatars offered during Profile Setup.
//  `rawValue` is the exact Assets.xcassets imageset name (note the literal space
//  in "energy drink" — must match the asset catalog folder name exactly).
//

import Foundation

enum AvatarOption: String, CaseIterable, Identifiable, Equatable {
    case coffee
    case boba
    case energyDrink = "energy drink"
    case milk
    case water

    var id: String { rawValue }

    /// Exact Assets.xcassets imageset name — pass directly to `Image(_:)`.
    var assetName: String { rawValue }

    var displayName: String {
        switch self {
        case .coffee: return "Coffee"
        case .boba: return "Boba"
        case .energyDrink: return "Energy Drink"
        case .milk: return "Strawberry Milk"
        case .water: return "Water Bottle"
        }
    }

    /// Picks a random default avatar — used when the user bypasses avatar selection
    /// entirely (e.g. taps "Skip for now" on Profile Setup).
    static func random() -> AvatarOption {
        allCases.randomElement() ?? .coffee
    }
}
