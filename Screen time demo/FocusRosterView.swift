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
    /// Each participant's avatar/photo info, keyed by UID — see `MemberAvatarView`.
    var memberAvatars: [String: UserProfile] = [:]
    let hostUid: String
    // See `KawaiiCardModifier` — guarantees this redraws with fresh `Color.theme.*` values.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Focus Roster", systemImage: "list.bullet.rectangle.portrait")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            if sortedParticipants.isEmpty {
                Text("Waiting for participants…")
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text.opacity(0.55))
            } else {
                ForEach(sortedParticipants) { participant in
                    FocusRosterRow(
                        name: memberNames[participant.id] ?? participant.id,
                        state: participant.state,
                        isHost: participant.id == hostUid,
                        avatarAssetName: memberAvatars[participant.id]?.avatarAssetName,
                        photoURL: memberAvatars[participant.id]?.photoURL
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
    let avatarAssetName: String?
    let photoURL: URL?
    // See `KawaiiCardModifier` — guarantees this redraws with fresh `Color.theme.*` values
    // even when `name`/`state`/`isHost` happen to be unchanged across a theme switch.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                MemberAvatarView(name: name, avatarAssetName: avatarAssetName, photoURL: photoURL, size: 36)

                Circle()
                    .fill(presenceColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.theme.surface, lineWidth: 2))
                    .shadow(color: presenceColor.opacity(0.45), radius: 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.theme.body())
                        .foregroundStyle(Color.theme.text)

                    if isHost {
                        Text("Host")
                            .font(.theme.caption(10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.theme.primary.opacity(0.5), in: Capsule())
                            .foregroundStyle(Color.theme.text)
                    }
                }

                Text(state.label)
                    .font(.theme.caption())
                    .foregroundStyle(presenceColor)
            }

            Spacer(minLength: 0)

            Image(systemName: state.systemImage)
                .foregroundStyle(presenceColor)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    /// Functional status colors — kept distinct from the pastel palette so
    /// presence state remains readable at a glance, per the reference screen's
    /// use of accent colors atop the neutral kawaii base.
    private var presenceColor: Color {
        switch state {
        case .focused: return Color(hex: "6FA287")
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
