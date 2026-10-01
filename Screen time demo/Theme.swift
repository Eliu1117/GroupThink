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
import UIKit

// MARK: - Palette

extension Color {
    /// Resolves every role against whichever `AppTheme` is currently selected in
    /// `ThemeSettings`. These are computed (not cached `let`s) so re-reading them after a
    /// theme change always reflects the new palette; `RootView` forces a full subtree
    /// rebuild on theme change (via `.id(themeSettings.theme)`) so views actually re-render.
    enum theme {
        /// Resolves against `effectiveTheme` (the in-progress Settings preview if one is
        /// active, otherwise the committed theme) rather than `theme` directly, so the
        /// Settings screen's own content can preview a swatch tap instantly without that
        /// change leaking out to the rest of the app until "Apply Everywhere" is tapped.
        private static var palette: ThemePalette { ThemeSettings.shared.effectiveTheme.palette }

        /// Primary actions, active states, highlights.
        static var primary: Color { .adaptive(light: palette.primaryLight, dark: palette.primaryDark) }
        /// Secondary actions, success/focused states.
        static var secondary: Color { .adaptive(light: palette.secondaryLight, dark: palette.secondaryDark) }
        /// Global screen background.
        static var background: Color { .adaptive(light: palette.backgroundLight, dark: palette.backgroundDark) }
        /// Text and icon foreground.
        static var text: Color { .adaptive(light: palette.textLight, dark: palette.textDark) }
        /// Floating card / list surface color.
        static var surface: Color { .adaptive(light: palette.surfaceLight, dark: palette.surfaceDark) }
        /// Break timers and success states.
        static var forestGreen: Color { .adaptive(light: palette.accentLight, dark: palette.accentDark) }
    }

    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
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

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b, alpha: 1)
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
///
/// Found to be the real explanation for the long-running "cards/buttons don't update live"
/// saga: `cornerRadius`/`padding` are this struct's ONLY stored properties, and they never
/// vary with the theme — so when only `ThemeSettings.shared.theme` changes, SwiftUI's
/// diffing sees an unchanged `KawaiiCardModifier` value and can skip re-invoking
/// `body(content:)` entirely, even though an ancestor view's `body` genuinely re-ran and
/// constructed a "fresh" (but value-identical) modifier. The `Color.theme.surface` read
/// inside never even gets a chance to re-evaluate. Holding a real `@ObservedObject`
/// subscription here (the same proven-reliable pattern as `KawaiiBackgroundModifier` below)
/// fixes this at the source, regardless of whether an ancestor happens to look "unchanged".
struct KawaiiCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    @ObservedObject private var themeSettings = ThemeSettings.shared

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

/// Backs `kawaiiBackground()`/`kawaiiListBackground()`. Holding `@ObservedObject` here (rather
/// than just reading the `Color.theme.*` static getters from a plain `View` extension function)
/// is what makes live theme switching actually repaint the screen: SwiftUI re-invokes a
/// `ViewModifier`'s `body(content:)` whenever an `@ObservedObject` it holds publishes a change,
/// which re-renders `content` and everything below it fresh — WITHOUT tearing down and
/// recreating the view's identity (unlike a `.id()`-keyed rebuild), so things like a
/// `NavigationStack`'s current push stack are preserved. Since nearly every screen in the app
/// applies one of these two modifiers near its root, this one hook is enough to make theme
/// changes repaint the whole app live.
private struct KawaiiBackgroundModifier: ViewModifier {
    var hidesScrollContentBackground: Bool
    @ObservedObject private var themeSettings = ThemeSettings.shared

    func body(content: Content) -> some View {
        if hidesScrollContentBackground {
            content
                .scrollContentBackground(.hidden)
                .background(Color.theme.background.ignoresSafeArea())
        } else {
            content
                .background(Color.theme.background.ignoresSafeArea())
        }
    }
}

extension View {
    func kawaiiCard(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(KawaiiCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    /// Lighter-weight grouping than `kawaiiCard()` — a soft tinted (not plain white) fill with
    /// no shadow, for subtly grouping related settings *inside* an already-elevated white
    /// card (e.g. Pomodoro settings nested inside the session-start card), where a second
    /// white-on-white card with its own shadow would read as visual noise rather than hierarchy.
    func subtleSettingCard(cornerRadius: CGFloat = 16, padding insetAmount: CGFloat = 14) -> some View {
        self.padding(insetAmount)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.theme.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Applies the cream background to an entire screen, ignoring safe areas.
    func kawaiiBackground() -> some View {
        modifier(KawaiiBackgroundModifier(hidesScrollContentBackground: false))
    }

    /// Applies the Velvet Brew look to List/Form-based screens: hides the default
    /// grouped gray background in favor of the cream backdrop, letting each
    /// Section's own white background read as a floating card in the gaps.
    func kawaiiListBackground() -> some View {
        modifier(KawaiiBackgroundModifier(hidesScrollContentBackground: true))
    }
}

// MARK: - Buttons

/// Primary pill button: pink fill, brown text, capsule shape.
///
/// Holds a real `@ObservedObject` for the same reason as `KawaiiCardModifier` above:
/// `isDisabled` is this style's only stored property and rarely changes alongside a theme
/// switch, so without a genuine subscription here `makeBody` can get skipped and the
/// `Color.theme.primary`-based fill never re-evaluates.
struct KawaiiPrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false
    @ObservedObject private var themeSettings = ThemeSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme.headline())
            .foregroundStyle(Color.theme.text)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
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
    // See `KawaiiPrimaryButtonStyle` — a real subscription guarantees `makeBody` re-runs on
    // theme change, since this style otherwise has no stored properties for SwiftUI to
    // notice have changed.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme.headline())
            .foregroundStyle(Color.theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Color.theme.text.opacity(0.35), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Red filled pill for stop/end/cancel actions — rounded capsule with solid color.
struct KawaiiDestructiveBorderedButtonStyle: ButtonStyle {
    var isDisabled: Bool = false
    // See `KawaiiPrimaryButtonStyle` for why this subscription is needed even though this
    // style's text color (`Color.white`) doesn't vary by theme — it does read `Color.theme`
    // nowhere directly today, but keeping the same reactive guarantee here protects against
    // this becoming theme-aware later without anyone remembering to re-add this.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme.headline())
            .foregroundStyle(Color.white.opacity(isDisabled ? 0.65 : 1))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Color.red.opacity(isDisabled ? 0.35 : 0.88),
                in: Capsule()
            )
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

extension ButtonStyle where Self == KawaiiDestructiveBorderedButtonStyle {
    static func kawaiiDestructive(isDisabled: Bool = false) -> KawaiiDestructiveBorderedButtonStyle {
        KawaiiDestructiveBorderedButtonStyle(isDisabled: isDisabled)
    }
}

/// For `Button`s whose label is a full-width row (e.g. a `KawaiiListRow`) that would
/// otherwise need `.buttonStyle(.plain)` to avoid list-row-wide highlighting. `.plain` alone
/// gives zero press feedback, which makes rows like Profile's "Settings" entry look
/// unresponsive/dead when tapped — this adds a quick highlight + scale-down instead.
struct KawaiiRowButtonStyle: ButtonStyle {
    @ObservedObject private var themeSettings = ThemeSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.theme.secondary.opacity(configuration.isPressed ? 0.22 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KawaiiRowButtonStyle {
    static var kawaiiRow: KawaiiRowButtonStyle { KawaiiRowButtonStyle() }
}

// MARK: - Toggle

/// Coffee-brown switch so the off-state thumb matches the outline, not Apple's white.
struct KawaiiToggleStyle: ToggleStyle {
    // See `KawaiiPrimaryButtonStyle` — without a real subscription, this style previously had
    // ZERO stored properties, meaning SwiftUI had no way to tell it needed to redraw with new
    // `Color.theme.*` values on a theme change.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    configuration.isOn.toggle()
                }
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.theme.primary : Color.theme.text.opacity(0.18))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Color.theme.text)
                            .padding(3)
                    }
                    .overlay(
                        Capsule().stroke(Color.theme.text.opacity(0.55), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "On" : "Off")
        }
    }
}

extension ToggleStyle where Self == KawaiiToggleStyle {
    static var kawaii: KawaiiToggleStyle { KawaiiToggleStyle() }
}

// MARK: - Reusable list row

/// Settings/stat row used inside a card: circular pastel icon, title/subtitle, chevron.
///
/// Almost every row's `icon`/`title`/`subtitle` text is static (e.g. "Minutes Earned"), so on
/// a theme change these stored properties are identical to the previous render — exactly the
/// pattern (see `KawaiiCardModifier`) that lets SwiftUI skip re-running `body` and leave the
/// `Color.theme.text`-based styling stale. This is almost certainly why screens built heavily
/// out of `KawaiiListRow` (e.g. the entire Profile tab) looked completely unaffected by theme
/// changes while other screens partially updated. A real subscription fixes it at the source.
struct KawaiiListRow: View {
    let icon: String
    let iconTint: Color
    let title: String
    let subtitle: String?
    var showChevron: Bool = true
    var action: (() -> Void)?
    @ObservedObject private var themeSettings = ThemeSettings.shared

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
        // When no `action` is supplied, this row is meant to be used as a *label* for some
        // other interactive container (e.g. a `NavigationLink`) rather than tappable itself.
        // Wrapping it in a `Button` and `.disabled(true)`-ing it in that case made it render
        // visibly grayed-out (SwiftUI dims disabled buttons by default) even though the
        // enclosing NavigationLink was fully functional. Render plain content instead.
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
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
}

// MARK: - Stat block (three-card row style, e.g. Minutes Earned / Streak)

struct KawaiiStatBlock: View {
    let icon: String
    let iconTint: Color
    let value: String
    let label: String
    // See `KawaiiListRow` — guarantees this redraws with fresh `Color.theme.*` values when
    // `value`/`label` (its only other stored properties) happen to be unchanged across a
    // theme change.
    @ObservedObject private var themeSettings = ThemeSettings.shared

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

// MARK: - Asset warm-up

/// Decodes every theme swatch image once, off the main thread, right after launch.
///
/// `UIImage(named:)` populates UIKit's internal by-name image cache, so by the time the
/// Settings color-theme grid (or the Boba flavor picker, or `ApplyingThemeView`) first
/// displays one of these via SwiftUI's `Image(_:)`, it's already decoded and cached rather
/// than being decoded synchronously on the main thread the first time it's laid out — which,
/// combined with a couple of these PNGs previously being an unnecessarily large 2000×2000px,
/// was the real cause of the Settings sheet feeling slow to appear.
enum ThemeAssetPrefetcher {
    static func warmCache() {
        let assetNames = AppTheme.allCases.map(\.assetName)
        Task.detached(priority: .utility) {
            for name in assetNames {
                _ = UIImage(named: name)
            }
        }
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
        // `doneButtonAppearance` was deprecated in iOS 26 in favor of `buttonAppearance`
        // alone covering all bar button roles (including "Done"), so it's no longer needed.

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
