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
            .navigationTitle("Session Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
            Image(systemName: heroSymbol)
                .font(.system(size: 64))
                .foregroundStyle(heroColor)
                .scaleEffect(heroVisible ? 1 : 0.2)
                .opacity(heroVisible ? 1 : 0)

            Text(heroTitle)
                .font(.title2.bold())

            Text("\(summary.groupName) · \(summary.actualMinutes) min session\(summary.wasStrictMode ? " · Strict" : "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        case .focused: return .yellow
        case .left: return .yellow
        case .opened: return .red
        default: return .green
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
            HStack {
                statBlock(
                    value: "+\(summary.minutesEarned)",
                    label: "Minutes Earned",
                    symbol: "clock.fill",
                    color: summary.minutesEarned > 0 ? .green : .secondary
                )

                Divider().frame(height: 44)

                statBlock(
                    value: profile.map { "\($0.focusMinutes)" } ?? "—",
                    label: "Total Minutes",
                    symbol: "sum",
                    color: .blue
                )

                Divider().frame(height: 44)

                statBlock(
                    value: profile.map { "\($0.currentStreak)" } ?? "—",
                    label: "Day Streak",
                    symbol: "flame.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .opacity(statsVisible ? 1 : 0)
        .offset(y: statsVisible ? 0 : 16)
    }

    private func statBlock(value: String, label: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session stats

    private var sessionStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group Outcome")
                .font(.headline)

            HStack(spacing: 12) {
                outcomePill(count: summary.focusedCount, label: "Focused", color: .green)
                outcomePill(count: summary.leftCount, label: "Left", color: .yellow)
                outcomePill(count: summary.openedCount, label: "Opened", color: .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .opacity(statsVisible ? 1 : 0)
        .offset(y: statsVisible ? 0 : 16)
    }

    private func outcomePill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count) \(label)")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Roster

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final Roster")
                .font(.headline)

            ForEach(Array(summary.rankedParticipants.enumerated()), id: \.element.id) { index, participant in
                HStack(spacing: 12) {
                    Image(systemName: participant.state.systemImage)
                        .foregroundStyle(stateColor(participant.state))
                        .frame(width: 24)

                    Text(summary.memberNames[participant.id] ?? "Member")
                        .fontWeight(participant.id == summary.myUID ? .semibold : .regular)

                    if participant.id == summary.myUID {
                        Text("You")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text(participant.state.label)
                        .font(.caption.weight(.medium))
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
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .opacity(rosterVisible ? 1 : 0)
    }

    private func stateColor(_ state: ParticipantState) -> Color {
        switch state {
        case .focused: return .green
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
