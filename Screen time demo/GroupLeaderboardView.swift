//
//  GroupLeaderboardView.swift
//  Screen time demo
//
//  Phase 5 — ranks group members by total focus minutes, with streaks.
//

import SwiftUI

struct GroupLeaderboardView: View {
    let group: Group
    let currentUserUID: String?
    let memberNames: [String: String]

    @StateObject private var viewModel = GroupLeaderboardViewModel()

    var body: some View {
        List {
            groupStreakSection

            Section("Rankings") {
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        leaderboardRow(rank: index + 1, entry: entry)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .kawaiiListBackground()
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load(group: group, knownNames: memberNames)
        }
        .task {
            await viewModel.load(group: group, knownNames: memberNames)
        }
    }

    // MARK: - Group streak

    private var groupStreakSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "E8B94A").opacity(0.3))
                        .frame(width: 56, height: 56)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(viewModel.groupStreak > 0 ? Color(hex: "E8B94A") : Color.theme.text.opacity(0.3))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.groupStreak) day\(viewModel.groupStreak == 1 ? "" : "s")")
                        .font(.theme.heading(20))
                        .foregroundStyle(Color.theme.text)
                    Text("Group streak")
                        .font(.theme.body())
                        .foregroundStyle(Color.theme.text.opacity(0.55))
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("The group streak survives only if every member completes a session each day.")
        }
    }

    // MARK: - Rows

    private func leaderboardRow(rank: Int, entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            rankBadge(rank)

            ZStack {
                Circle()
                    .fill(Color.theme.primary.opacity(0.35))
                    .frame(width: 32, height: 32)
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(Color.theme.text)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.theme.body())
                        .fontWeight(entry.id == currentUserUID ? .semibold : .regular)
                        .foregroundStyle(Color.theme.text)

                    if entry.id == currentUserUID {
                        Text("You")
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.5))
                    }
                }

                Text(formattedMinutes(entry.focusMinutes))
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.55))
            }

            Spacer(minLength: 0)

            if entry.currentStreak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color(hex: "E8B94A"))
                    Text("\(entry.currentStreak)")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.text)
                }
                .font(.theme.body(14))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.theme.body(14).bold().monospacedDigit())
            .foregroundStyle(rank <= 3 ? Color.theme.text : Color.theme.text.opacity(0.5))
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(rankColor(rank))
            )
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "E8B94A").opacity(0.6)
        case 2: return Color.theme.text.opacity(0.15)
        case 3: return Color.theme.primary.opacity(0.5)
        default: return Color.theme.background
        }
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h focused" : "\(hours)h \(remainder)m focused"
        }
        return "\(minutes) min focused"
    }
}

#Preview {
    NavigationStack {
        GroupLeaderboardView(
            group: Group(
                id: "preview",
                name: "Finals Crew",
                inviteCode: "K7Q2Z9",
                createdBy: "user1",
                memberUids: ["user1", "user2"],
                currentGroupStreak: 3
            ),
            currentUserUID: "user1",
            memberNames: ["user1": "Ethan", "user2": "David"]
        )
    }
}
