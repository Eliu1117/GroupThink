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

    // MARK: - GRO-9: Host blocklist serialisation

    /// Encodes the current selection as a base64 string for Firestore storage.
    func encodedAsBase64() -> String? {
        guard let data = try? PropertyListEncoder().encode(selection) else { return nil }
        return data.base64EncodedString()
    }

    /// Decodes a base64 string (produced by `encodedAsBase64`) back into a selection.
    /// Returns nil if decoding fails, which is expected when the base64 was encoded on a
    /// different device (ApplicationToken values are opaque and device-local).
    static func decodeFromBase64(_ base64: String) -> FamilyActivitySelection? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
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
