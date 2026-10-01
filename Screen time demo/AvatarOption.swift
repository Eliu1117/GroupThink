//
//  AvatarOption.swift
//  Screen time demo
//
//  The built-in "cute drink character" avatars offered during Profile Setup.
//  `rawValue` is the exact Assets.xcassets imageset name (note the literal spaces in e.g.
//  "energy drink"/"purple energy drink" — must match the asset catalog folder name exactly).
//
//  Every avatar belongs to a `Family` (coffee / boba / energy drink / milk / water). Each
//  family gets exactly one cell in the primary grid, represented by its `mainOption` — the
//  rest of that family's cases are "skins": alternate color-scheme variants of the same
//  character, surfaced via a secondary skin picker (see `ProfileSetupView.skinPicker`)
//  instead of each getting their own grid cell. Originated with the Boba family
//  (`.boba`/`.taroBoba`/`.matchaBoba`) and extended to every other family once their skin
//  artwork was added.
//

import Foundation

enum AvatarOption: String, CaseIterable, Identifiable, Equatable {
    case coffee
    case cappuccino = "cappucino"
    /// Classic milk-tea boba — the "main" Boba avatar.
    case boba
    /// Purple/taro palette variant of Boba.
    case taroBoba = "taro-boba"
    /// Green/matcha palette variant of Boba.
    case matchaBoba = "matcha-boba"
    case energyDrink = "energy drink"
    case purpleEnergyDrink = "purple energy drink"
    case greenEnergyDrink = "green energy drink"
    case milk
    case strawberryMilk = "strawberry-milk"
    case chocolateMilk = "chocolate-milk"
    case water
    case pinkWater = "pink-water"
    case greenWater = "green-water"

    var id: String { rawValue }

    /// Exact Assets.xcassets imageset name — pass directly to `Image(_:)`.
    var assetName: String { rawValue }

    var displayName: String {
        switch self {
        case .coffee: return "Coffee"
        case .cappuccino: return "Cappuccino"
        case .boba: return "Boba"
        case .taroBoba: return "Taro Boba"
        case .matchaBoba: return "Matcha Boba"
        case .energyDrink: return "Energy Drink"
        case .purpleEnergyDrink: return "Purple Energy Drink"
        case .greenEnergyDrink: return "Green Energy Drink"
        case .milk: return "Milk"
        case .strawberryMilk: return "Strawberry Milk"
        case .chocolateMilk: return "Chocolate Milk"
        case .water: return "Water Bottle"
        case .pinkWater: return "Pink Water"
        case .greenWater: return "Green Water"
        }
    }

    /// Which base-avatar family this skin belongs to.
    enum Family: CaseIterable, Equatable {
        case coffee, boba, energyDrink, milk, water

        /// The default skin representing this family in the primary grid.
        var mainOption: AvatarOption {
            switch self {
            case .coffee: return .coffee
            case .boba: return .boba
            case .energyDrink: return .energyDrink
            case .milk: return .milk
            case .water: return .water
            }
        }

        var displayName: String {
            switch self {
            case .coffee: return "Coffee"
            case .boba: return "Boba"
            case .energyDrink: return "Energy Drink"
            case .milk: return "Milk"
            case .water: return "Water"
            }
        }
    }

    var family: Family {
        switch self {
        case .coffee, .cappuccino: return .coffee
        case .boba, .taroBoba, .matchaBoba: return .boba
        case .energyDrink, .purpleEnergyDrink, .greenEnergyDrink: return .energyDrink
        case .milk, .strawberryMilk, .chocolateMilk: return .milk
        case .water, .pinkWater, .greenWater: return .water
        }
    }

    /// Avatars that each get their own cell in the Profile Setup grid — one per `Family`,
    /// via `Family.mainOption`. Skin variants are deliberately excluded here; they're
    /// surfaced instead via `familySkins`/the skin picker once their family's grid cell is
    /// the active selection.
    static var primaryGridOptions: [AvatarOption] {
        Family.allCases.map(\.mainOption)
    }

    /// All skin variants within this avatar's family, in display order — relies on
    /// declaration order above always listing each family's main case first.
    var familySkins: [AvatarOption] {
        AvatarOption.allCases.filter { $0.family == family }
    }

    /// Whether this avatar's family has more than one skin, i.e. whether a skin picker
    /// should be surfaced once this family's grid cell is the active selection.
    var hasSkinVariants: Bool { familySkins.count > 1 }

    /// Short flavor name used in the skin picker (vs. the full `displayName`, and vs. the
    /// family-name section header shown above the picker).
    var skinLabel: String {
        switch self {
        case .coffee, .boba, .energyDrink, .milk, .water: return "Classic"
        case .cappuccino: return "Cappuccino"
        case .taroBoba: return "Taro"
        case .matchaBoba: return "Matcha"
        case .purpleEnergyDrink: return "Purple"
        case .greenEnergyDrink: return "Green"
        case .strawberryMilk: return "Strawberry"
        case .chocolateMilk: return "Chocolate"
        case .pinkWater: return "Pink"
        case .greenWater: return "Green"
        }
    }

    /// Picks a random default avatar — used when the user bypasses avatar selection
    /// entirely (e.g. taps "Skip for now" on Profile Setup). Only picks from the primary
    /// grid options (not skin variants) to keep this "one of the 5 defaults".
    static func random() -> AvatarOption {
        primaryGridOptions.randomElement() ?? .coffee
    }
}
