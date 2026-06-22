//
//  StudyHallShieldConfiguration.swift
//  StudyHallShield
//
//  ShieldActionDelegate — fires on every user tap of the shield OK button.
//
//  ShieldConfigurationDataSource.configuration(shielding:) is cached by iOS per
//  app instance and therefore does NOT fire on every blocked-app attempt.
//  ShieldActionDelegate.handle(action:) is an explicit user interaction callback
//  that has no caching and fires synchronously for every shield dismissal.
//

import ManagedSettings
import ManagedSettingsUI

final class StudyHallShieldConfiguration: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: Application,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        reportOpenedInstantly(origin: "application")
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for application: Application,
        in category: ActivityCategory,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        // Strict mode: apps are blocked by category (.all except whitelist).
        reportOpenedInstantly(origin: "category")
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomain,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        reportOpenedInstantly(origin: "webDomain")
        completionHandler(.close)
    }

    private func reportOpenedInstantly(origin: String) {
        print("[Shield Extension] Shield dismissed (\(origin)) — enqueueing opened state")
        ExtensionFirebaseWriter.markOpenedFromBackground(source: .shield)
    }
}
