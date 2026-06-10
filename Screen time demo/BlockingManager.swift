//
//  BlockingManager.swift
//  Screen time demo
//

import FamilyControls
import ManagedSettings

final class BlockingManager {
    static let shared = BlockingManager()

    private let store = ManagedSettingsStore()

    private init() {}

    func block(selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = .specific(selection.categoryTokens)
    }

    /// Strict mode: shields ALL app categories except the user's locally-chosen
    /// whitelist. No tokens cross devices — the "block everything" policy is a plain
    /// Bool in Firestore and each device carves out its own exceptions.
    func blockStrict(whitelist: FamilyActivitySelection) {
        store.shield.applications = nil
        store.shield.applicationCategories = .all(except: whitelist.applicationTokens)
    }

    func clear() {
        store.clearAllSettings()
    }
}
