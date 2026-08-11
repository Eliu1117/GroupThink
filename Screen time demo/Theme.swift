//
//  Theme.swift
//  Screen time demo
//
//  "Velvet Brew" design system — kawaii coffeeshop theme. Centralizes the
//  color palette, typography, and reusable view modifiers used across the
//  UI overhaul so individual screens never hardcode hex values or system
//  colors directly.
//

import SwiftUI

// MARK: - Palette

extension Color {
    enum theme {
        /// Strawberry milk pink — primary actions, active states, highlights.
        static let primary = Color(hex: "FADADD")
        /// Matcha green — secondary actions, success/focused states.
        static let secondary = Color(hex: "D0E8D0")
        /// Vanilla cream — global screen background.
        static let background = Color(hex: "FDF5E6")
        /// Coffee brown — all text and icon foreground color.
        static let text = Color(hex: "6F4E37")
        /// Floating card / list surface color.
        static let surface = Color.white
    }
}

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Typography

extension Font {
    enum theme {
        static func heading(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }

        static func headline(_ size: CGFloat = 17) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        static func body(_ size: CGFloat = 16) -> Font {
            .system(size: size, weight: .medium, design: .rounded)
        }

        static func caption(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .medium, design: .rounded)
        }
    }
}

// MARK: - Card modifier

/// Floating white card: rounded corners + soft diffuse shadow.
struct KawaiiCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func kawaiiCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(KawaiiCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    /// Applies the cream background to an entire screen, ignoring safe areas.
    func kawaiiBackground() -> some View {
        background(Color.theme.background.ignoresSafeArea())
    }

    /// Applies the Velvet Brew look to List/Form-based screens: hides the default
    /// grouped gray background in favor of the cream backdrop, letting each
    /// Section's own white background read as a floating card in the gaps.
    func kawaiiListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.theme.background.ignoresSafeArea())
    }
}

// MARK: - Buttons

/// Primary pill button: pink fill, brown text, capsule shape.
struct KawaiiPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme.headline())
            .foregroundStyle(Color.theme.text)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                isDisabled ? Color.theme.primary.opacity(0.4) : Color.theme.primary,
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Secondary/outlined pill button: brown stroke, brown text, capsule shape.
struct KawaiiOutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme.headline())
            .foregroundStyle(Color.theme.text)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Color.theme.text.opacity(0.35), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == KawaiiPrimaryButtonStyle {
    static func kawaiiPrimary(isDisabled: Bool = false) -> KawaiiPrimaryButtonStyle {
        KawaiiPrimaryButtonStyle(isDisabled: isDisabled)
    }
}

extension ButtonStyle where Self == KawaiiOutlinedButtonStyle {
    static var kawaiiOutlined: KawaiiOutlinedButtonStyle { KawaiiOutlinedButtonStyle() }
}

// MARK: - Reusable list row

/// Settings/stat row used inside a card: circular pastel icon, title/subtitle, chevron.
struct KawaiiListRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    var showChevron: Bool = true
    var action: (() -> Void)?

    init(
        icon: String,
        iconTint: Color = .theme.primary,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
        self.action = action
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.35))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .foregroundStyle(Color.theme.text)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.theme.body())
                        .foregroundStyle(Color.theme.text)

                    if let subtitle {
                        Text(subtitle)
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                    }
                }

                Spacer(minLength: 0)

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.theme.text.opacity(0.35))
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Stat block (three-card row style, e.g. Minutes Earned / Streak)

struct KawaiiStatBlock: View {
    let icon: String
    let iconTint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.35))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.theme.text)
            }

            Text(value)
                .font(.theme.heading(20))
                .foregroundStyle(Color.theme.text)
                .contentTransition(.numericText())

            Text(label)
                .font(.theme.caption())
                .foregroundStyle(Color.theme.text.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .kawaiiCard(cornerRadius: 18, padding: 8)
    }
}

// MARK: - Global navigation bar styling

enum KawaiiAppearance {
    /// Applies the Velvet Brew theme to UIKit-backed chrome (nav bars, tab bars)
    /// that SwiftUI's `.navigationTitle`/`TabView` render under the hood.
    static func apply() {
        let textColor = UIColor(Color.theme.text)
        let backgroundColor = UIColor(Color.theme.background)

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = backgroundColor
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [.foregroundColor: textColor]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: textColor]
        navAppearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: textColor]
        navAppearance.doneButtonAppearance.normal.titleTextAttributes = [.foregroundColor: textColor]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = textColor

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = backgroundColor
        tabAppearance.shadowColor = .clear

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = textColor.withAlphaComponent(0.5)
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: textColor.withAlphaComponent(0.5)]
        itemAppearance.selected.iconColor = textColor
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: textColor]
        tabAppearance.stackedLayoutAppearance = itemAppearance
        tabAppearance.inlineLayoutAppearance = itemAppearance
        tabAppearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor(Color.theme.primary)

        UITableView.appearance().backgroundColor = backgroundColor
        UITableViewCell.appearance().backgroundColor = .clear
    }
}
