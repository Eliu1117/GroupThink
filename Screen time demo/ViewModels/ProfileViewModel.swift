//
//  ProfileViewModel.swift
//  Screen time demo
//

import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var notificationsEnabled = false

    func refresh() async {
        await NotificationManager.shared.refreshAuthorizationStatus()
        notificationsEnabled = NotificationManager.shared.isAuthorized
    }

    func enableNotifications() async {
        await NotificationManager.shared.requestAuthorization()
        notificationsEnabled = NotificationManager.shared.isAuthorized
    }
}
