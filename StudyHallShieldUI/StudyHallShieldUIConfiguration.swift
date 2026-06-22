//
//  StudyHallShieldUIConfiguration.swift
//  StudyHallShieldUI
//
//  ShieldConfigurationDataSource — customises the visual appearance of the shield overlay.
//  Opened-app detection is handled separately by StudyHallShield (ShieldActionDelegate),
//  which fires on every shield dismissal and is immune to iOS configuration caching.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

final class StudyHallShieldUIConfiguration: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        studyHallShield
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        studyHallShield
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        studyHallShield
    }

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
}
