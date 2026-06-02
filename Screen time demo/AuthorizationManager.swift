//
//  AuthorizationManager.swift
//  Screen time demo
//

import Combine
import FamilyControls

@MainActor
final class AuthorizationManager: ObservableObject {
    static let shared = AuthorizationManager()

    @Published private(set) var isAuthorized = false

    private init() {
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
