//
//  BlocklistStore.swift
//  Screen time demo
//
//  Persists the user's locally chosen FamilyActivitySelection.
//
//  Family Controls tokens are opaque and device-specific, so each member picks and
//  stores their OWN blocklist. The selection is saved in an App Group container so the
//  DeviceActivityMonitor extension can read the same selection the app wrote.
//

import FamilyControls
import Foundation

@MainActor
final class BlocklistStore: ObservableObject {
    static let shared = BlocklistStore()

    /// Must match the App Group capability added to both the app and the monitor extension.
    static let appGroupID = "group.com.davechengapps.screentimedemo"
    private static let selectionKey = "blocklist.selection"

    @Published var selection: FamilyActivitySelection {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    private init() {
        defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        if
            let data = defaults.data(forKey: Self.selectionKey),
            let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        {
            selection = decoded
        } else {
            selection = FamilyActivitySelection()
        }
    }

    var selectedCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var hasSelection: Bool { selectedCount > 0 }

    private func persist() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Self.selectionKey)
    }
}
