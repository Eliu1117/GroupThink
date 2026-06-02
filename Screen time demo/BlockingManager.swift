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

    func clear() {
        store.clearAllSettings()
    }
}
