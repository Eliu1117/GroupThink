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
                Image(systemName: "flame.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(viewModel.groupStreak > 0 ? .orange : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.groupStreak) day\(viewModel.groupStreak == 1 ? "" : "s")")
                        .font(.title2.bold())
                    Text("Group streak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .fontWeight(entry.id == currentUserUID ? .semibold : .regular)

                    if entry.id == currentUserUID {
                        Text("You")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(formattedMinutes(entry.focusMinutes))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if entry.currentStreak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(entry.currentStreak)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.subheadline.bold().monospacedDigit())
            .foregroundStyle(rank <= 3 ? .white : .secondary)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(rankColor(rank))
            )
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return Color(.systemGray5)
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
