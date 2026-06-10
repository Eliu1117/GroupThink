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

    /// GRO-9: Applies a merged shield from the personal selection and an optional host
    /// selection. The union of both token sets is enforced on this device.
    func blockMerged(personal: FamilyActivitySelection, host: FamilyActivitySelection?) {
        var appTokens = personal.applicationTokens
        var categoryTokens = personal.categoryTokens

        if let host {
            appTokens.formUnion(host.applicationTokens)
            categoryTokens.formUnion(host.categoryTokens)
        }

        store.shield.applications = appTokens.isEmpty ? nil : appTokens
        store.shield.applicationCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)
    }

    func clear() {
        store.clearAllSettings()
    }
}
