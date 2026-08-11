//
//  SessionSummaryView.swift
//  Screen time demo
//
//  Animated end-of-session summary: personal result, group roster outcome,
//  and updated lifetime stats.
//

import SwiftUI

struct SessionSummaryView: View {
    let summary: SessionSummary

    @Environment(\.dismiss) private var dismiss
    @State private var heroVisible = false
    @State private var statsVisible = false
    @State private var rosterVisible = false
    @State private var profile: UserProfile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    personalResultCard
                    sessionStatsCard
                    rosterCard
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
            .task {
                let profiles = await UserService.shared.fetchProfiles(for: [summary.myUID])
                withAnimation(.snappy) {
                    profile = profiles[summary.myUID]
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
            rosterVisible = true
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

            Text("\(summary.groupName) · \(summary.actualMinutes) min session\(summary.wasStrictMode ? " · Strict" : "")")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.6))
                // GRO-40: back-to-back cycle progress + early-end indicator.
                if summary.isPomodoroCycle {
                    Text(
                        "Pomodoro cycle: \(summary.completedSessionIndex) of \(summary.totalSessionsInCycle) sessions"
                            + (summary.cycleEndedEarly ? " · ended early" : "")
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(summary.cycleEndedEarly ? .orange : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (summary.cycleEndedEarly ? Color.orange : Color.secondary).opacity(0.12),
                        in: Capsule()
                    )
                }

        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var heroSymbol: String {
        switch summary.myState {
        case .focused: return "trophy.fill"
        case .left: return "figure.walk.departure"
        case .opened: return "exclamationmark.triangle.fill"
        default: return "checkmark.seal.fill"
        }
    }

    private var heroColor: Color {
        switch summary.myState {
        case .focused: return Color(hex: "E8B94A")
        case .left: return Color(hex: "E8B94A")
        case .opened: return .red
        default: return Color(hex: "6FA287")
        }
    }

    private var heroTitle: String {
        switch summary.myState {
        case .focused: return "You stayed focused!"
        case .left: return "You left early"
        case .opened: return "You opened a blocked app"
        default: return "Session complete"
        }
    }

    // MARK: - Personal result

    private var personalResultCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                KawaiiStatBlock(
                    icon: "clock.fill",
                    iconTint: summary.minutesEarned > 0 ? Color.green : Color.theme.secondary,
                    value: "+\(summary.minutesEarned)",
                    label: summary.isPomodoroCycle ? "Cycle Minutes" : "Minutes Earned"
                )
                KawaiiStatBlock(
                    icon: "sum",
                    iconTint: Color.theme.primary,
                    value: profile.map { "\($0.focusMinutes)" } ?? "—",
                    label: "Total Minutes"
                )
                KawaiiStatBlock(
                    icon: "flame.fill",
                    iconTint: Color(hex: "E8B94A").opacity(0.6),
                    value: profile.map { "\($0.currentStreak)" } ?? "—",
                    label: "Day Streak"
                )
            }

        }
        .opacity(statsVisible ? 1 : 0)
        .offset(y: statsVisible ? 0 : 16)
    }

    // MARK: - Session stats

    private var sessionStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group Outcome")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            HStack(spacing: 12) {
                outcomePill(count: summary.focusedCount, label: "Focused", color: Color(hex: "6FA287"))
                outcomePill(count: summary.leftCount, label: "Left", color: .yellow)
                outcomePill(count: summary.openedCount, label: "Opened", color: .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kawaiiCard()
        .opacity(statsVisible ? 1 : 0)
        .offset(y: statsVisible ? 0 : 16)
    }

    private func outcomePill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count) \(label)")
                .font(.theme.body(14))
                .foregroundStyle(Color.theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Roster

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final Roster")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            ForEach(Array(summary.rankedParticipants.enumerated()), id: \.element.id) { index, participant in
                HStack(spacing: 12) {
                    Image(systemName: participant.state.systemImage)
                        .foregroundStyle(stateColor(participant.state))
                        .frame(width: 24)

                    Text(summary.memberNames[participant.id] ?? "Member")
                        .font(.theme.body())
                        .fontWeight(participant.id == summary.myUID ? .semibold : .regular)
                        .foregroundStyle(Color.theme.text)

                    if participant.id == summary.myUID {
                        Text("You")
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.5))
                    }

                    Spacer(minLength: 0)

                    Text(participant.state.label)
                        .font(.theme.caption())
                        .foregroundStyle(stateColor(participant.state))
                }
                .padding(.vertical, 6)
                .opacity(rosterVisible ? 1 : 0)
                .offset(y: rosterVisible ? 0 : 12)
                .animation(
                    .easeOut(duration: 0.3).delay(0.45 + Double(index) * 0.07),
                    value: rosterVisible
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kawaiiCard()
        .opacity(rosterVisible ? 1 : 0)
    }

    private func stateColor(_ state: ParticipantState) -> Color {
        switch state {
        case .focused: return Color(hex: "6FA287")
        case .left: return .yellow
        case .opened: return .red
        case .break: return .orange
        }
    }
}

#Preview {
    SessionSummaryView(
        summary: SessionSummary(
            id: "preview",
            groupName: "Finals Crew",
            durationMin: 25,
            startAt: Date().addingTimeInterval(-25 * 60),
            endedAt: Date(),
            participants: [
                SessionParticipant(id: "u1", state: .focused),
                SessionParticipant(id: "u2", state: .left),
                SessionParticipant(id: "u3", state: .opened),
            ],
            memberNames: ["u1": "Ethan", "u2": "David", "u3": "Sam"],
            myUID: "u1",
            myState: .focused,
            minutesEarned: 25,
            wasStrictMode: true
        )
    )
}
