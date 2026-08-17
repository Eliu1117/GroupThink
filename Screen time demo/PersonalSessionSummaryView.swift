//
//  PersonalSessionSummaryView.swift
//  Screen time demo
//
//  Animated end-of-solo-session summary. Mirrors SessionSummaryView's hero/card/animation
//  pattern for a consistent feel, but swaps the group-outcome + roster cards for a single
//  "Access Attempts" card since a personal session has no other participants.
//

import SwiftUI

struct PersonalSessionSummaryView: View {
    let summary: PersonalSessionSummary

    @Environment(\.dismiss) private var dismiss
    @State private var heroVisible = false
    @State private var statsVisible = false
    @State private var attemptsVisible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    sessionStatsCard
                    accessAttemptsCard
                }
                .padding()
            }
            .kawaiiBackground()
            .navigationTitle("Session Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Color.theme.primary)
                }
            }
            .onAppear { runEntranceAnimation() }
        }
    }

    private func runEntranceAnimation() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            heroVisible = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.25)) {
            statsVisible = true
        }
        withAnimation(.easeOut(duration: 0.35).delay(0.45)) {
            attemptsVisible = true
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(heroColor.opacity(0.25))
                    .frame(width: 108, height: 108)
                Image(systemName: heroSymbol)
                    .font(.system(size: 48))
                    .foregroundStyle(heroColor)
            }
            .scaleEffect(heroVisible ? 1 : 0.2)
            .opacity(heroVisible ? 1 : 0)

            Text(heroTitle)
                .font(.theme.heading(22))
                .foregroundStyle(Color.theme.text)

            Text("\(summary.actualMinutes.durationPhrase) focus session\(summary.wasStrictMode ? " · Strict" : "")")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var heroSymbol: String {
        if summary.openedBlockedAppCount > 0 { return "exclamationmark.triangle.fill" }
        if summary.endedEarly { return "figure.walk.departure" }
        return "trophy.fill"
    }

    private var heroColor: Color {
        if summary.openedBlockedAppCount > 0 { return .red }
        if summary.endedEarly { return Color(hex: "E8B94A") }
        return Color(hex: "6FA287")
    }

    private var heroTitle: String {
        if summary.openedBlockedAppCount > 0 { return "You opened a blocked app" }
        if summary.endedEarly { return "You stopped early" }
        return "You stayed focused!"
    }

    // MARK: - Session stats

    private var sessionStatsCard: some View {
        HStack(spacing: 12) {
            KawaiiStatBlock(
                icon: "clock.fill",
                iconTint: Color.theme.secondary,
                value: "\(summary.actualMinutes)",
                label: "Minutes Focused"
            )
            KawaiiStatBlock(
                icon: "target",
                iconTint: Color.theme.primary,
                value: "\(summary.plannedDurationMin)",
                label: "Planned"
            )
            KawaiiStatBlock(
                icon: "lock.shield.fill",
                iconTint: summary.wasStrictMode ? Color.theme.secondary : Color.theme.text.opacity(0.2),
                value: summary.wasStrictMode ? "On" : "Off",
                label: "Strict Mode"
            )
        }
        .opacity(statsVisible ? 1 : 0)
        .offset(y: statsVisible ? 0 : 16)
    }

    // MARK: - Access attempts

    private var accessAttemptsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Access Attempts")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            HStack(spacing: 12) {
                Image(systemName: summary.openedBlockedAppCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(summary.openedBlockedAppCount > 0 ? .red : Color(hex: "6FA287"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(attemptsTitle)
                        .font(.theme.body())
                        .foregroundStyle(Color.theme.text)
                    Text(attemptsSubtitle)
                        .font(.theme.caption())
                        .foregroundStyle(Color.theme.text.opacity(0.55))
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kawaiiCard()
        .opacity(attemptsVisible ? 1 : 0)
        .offset(y: attemptsVisible ? 0 : 16)
    }

    private var attemptsTitle: String {
        summary.openedBlockedAppCount == 0
            ? "No blocked apps opened"
            : "\(summary.openedBlockedAppCount) blocked app attempt\(summary.openedBlockedAppCount == 1 ? "" : "s")"
    }

    private var attemptsSubtitle: String {
        summary.openedBlockedAppCount == 0
            ? "You didn't try to access anything on your blocklist."
            : "You dismissed a shield to try to open a blocked app or category."
    }
}

#Preview {
    PersonalSessionSummaryView(
        summary: PersonalSessionSummary(
            id: "preview",
            plannedDurationMin: 25,
            startAt: Date().addingTimeInterval(-25 * 60),
            endedAt: Date(),
            wasStrictMode: true,
            endedEarly: true,
            openedBlockedAppCount: 0
        )
    )
}
