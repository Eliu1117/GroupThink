//
//  AuthorizationManager.swift
//  Screen time demo
//

import Combine
import FamilyControls
import Foundation

@MainActor
final class AuthorizationManager: ObservableObject {
    static let shared = AuthorizationManager()

    @Published private(set) var isAuthorized = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // AuthorizationCenter is itself an ObservableObject. Observing its
        // objectWillChange keeps isAuthorized in sync even when the user grants
        // or revokes permission from the iOS Settings app while the app is running.
        AuthorizationCenter.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshAuthorizationStatus()
            }
            .store(in: &cancellables)

        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuthorizationStatus()
        } catch {
            isAuthorized = false
        }
    }
}
