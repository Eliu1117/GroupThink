//
//  FocusRosterView.swift
//  Screen time demo
//
//  GRO-18: Renamed from PresenceLeaderboardView — this component tracks live
//  presence status (focused / left / opened), not point values.
//

import SwiftUI

/// Live participant roster displayed in the lobby and active session screens.
struct FocusRosterView: View {
    let participants: [SessionParticipant]
    let memberNames: [String: String]
    let hostUid: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Focus Roster", systemImage: "list.bullet.rectangle.portrait")
                .font(.headline)

            if sortedParticipants.isEmpty {
                Text("Waiting for participants…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedParticipants) { participant in
                    FocusRosterRow(
                        name: memberNames[participant.id] ?? participant.id,
                        state: participant.state,
                        isHost: participant.id == hostUid
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.snappy, value: sortedParticipants)
    }

    private var sortedParticipants: [SessionParticipant] {
        participants.sorted { lhs, rhs in
            let rankL = presenceRank(lhs.state)
            let rankR = presenceRank(rhs.state)
            if rankL != rankR { return rankL < rankR }
            return (memberNames[lhs.id] ?? lhs.id) < (memberNames[rhs.id] ?? rhs.id)
        }
    }

    /// Lower rank surfaces higher on the roster (opened-app offenders first).
    private func presenceRank(_ state: ParticipantState) -> Int {
        switch state {
        case .opened: return 0
        case .left: return 1
        case .break: return 2
        case .focused: return 3
        }
    }
}

private struct FocusRosterRow: View {
    let name: String
    let state: ParticipantState
    let isHost: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(presenceColor)
                .frame(width: 12, height: 12)
                .shadow(color: presenceColor.opacity(0.45), radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body.weight(.medium))

                    if isHost {
                        Text("Host")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }

                Text(state.label)
                    .font(.caption)
                    .foregroundStyle(presenceColor)
            }

            Spacer(minLength: 0)

            Image(systemName: state.systemImage)
                .foregroundStyle(presenceColor)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(presenceColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var presenceColor: Color {
        switch state {
        case .focused: return .green
        case .left: return .yellow
        case .opened: return .red
        case .break: return .orange
        }
    }
}

#Preview {
    FocusRosterView(
        participants: [
            SessionParticipant(id: "u1", state: .focused),
            SessionParticipant(id: "u2", state: .opened),
            SessionParticipant(id: "u3", state: .left),
        ],
        memberNames: ["u1": "Alex", "u2": "Jordan", "u3": "Sam"],
        hostUid: "u1"
    )
    .padding()
}
