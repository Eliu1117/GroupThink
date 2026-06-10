//
//  BlocklistStore.swift
//  Screen time demo
//
//  Persists the user's FamilyActivitySelection for session blocking (App Group shared with extension).
//

import FamilyControls
import Foundation

final class BlocklistStore {
    static let shared = BlocklistStore()

    private var defaults: UserDefaults {
        UserDefaults(suiteName: StudyHallConstants.appGroupID) ?? .standard
    }

    private init() {
        migrateFromStandardDefaultsIfNeeded()
    }

    var selection: FamilyActivitySelection {
        get {
            guard
                let data = defaults.data(forKey: StudyHallConstants.blocklistDefaultsKey),
                let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
            else {
                return FamilyActivitySelection()
            }
            return decoded
        }
        set {
            guard let data = try? PropertyListEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: StudyHallConstants.blocklistDefaultsKey)
        }
    }

    var hasSelection: Bool {
        let selection = selection
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    // MARK: - Strict-mode whitelist

    /// Apps the user keeps available during strict-mode sessions (everything else is shielded).
    var whitelistSelection: FamilyActivitySelection {
        get {
            guard
                let data = defaults.data(forKey: StudyHallConstants.whitelistDefaultsKey),
                let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
            else {
                return FamilyActivitySelection()
            }
            return decoded
        }
        set {
            guard let data = try? PropertyListEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: StudyHallConstants.whitelistDefaultsKey)
        }
    }

    var whitelistCount: Int {
        whitelistSelection.applicationTokens.count
    }

    private func migrateFromStandardDefaultsIfNeeded() {
        let key = StudyHallConstants.blocklistDefaultsKey
        guard defaults.data(forKey: key) == nil,
              let legacyData = UserDefaults.standard.data(forKey: key)
        else { return }

        defaults.set(legacyData, forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
