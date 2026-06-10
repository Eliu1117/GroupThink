//
//  StudyHallShieldConfiguration.swift
//  StudyHallShield
//
//  Instant "opened" detection — fires when the system requests shield UI for a blocked app.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

final class StudyHallShieldConfiguration: ShieldConfigurationDataSource {
    private var studyHallShield: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.systemOrange.withAlphaComponent(0.18),
            icon: UIImage(systemName: "books.vertical.fill"),
            title: ShieldConfiguration.Label(text: "Study Hall", color: .label),
            subtitle: ShieldConfiguration.Label(
                text: "This app is blocked during your focus session.",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .label),
            primaryButtonBackgroundColor: .systemOrange
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        reportOpenedInstantly(origin: "application")
        return studyHallShield
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        reportOpenedInstantly(origin: "category")
        return studyHallShield
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        reportOpenedInstantly(origin: "webDomain")
        return studyHallShield
    }

    private func reportOpenedInstantly(origin: String) {
        print("[Shield Extension] Shield rendered (\(origin)) — enqueueing opened state")
        ExtensionFirebaseWriter.markOpenedFromBackground(source: .shield)
    }
}
