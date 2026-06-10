//
//  SessionView.swift
//  Screen time demo
//
//  Lobby and active session UI driven by Firestore real-time state.
//

import SwiftUI

struct SessionView: View {
    @ObservedObject var viewModel: SessionViewModel
    let memberNames: [String: String]

    var body: some View {
        if let session = viewModel.session {
            switch session.status {
            case .lobby:
                lobbyContent(session)
            case .active:
                activeContent(session)
            case .ended:
                EmptyView()
            }
        }
    }

    // MARK: - Lobby

    private func lobbyContent(_ session: StudySession) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Study Hall Lobby", systemImage: "person.3.sequence.fill")
                    .font(.headline)

                Text("\(session.durationMin)-minute session · waiting to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                participantRoster(session)

                lobbyActions(session)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func lobbyActions(_ session: StudySession) -> some View {
        if !viewModel.isInLobby {
            Button {
                Task { await viewModel.joinLobby() }
            } label: {
                Label("Join Lobby", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSubmitting)
        }

        if viewModel.isHost {
            Button {
                Task { await viewModel.launchSession() }
            } label: {
                Label("Launch Session", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(viewModel.isSubmitting || session.participants.isEmpty)
        }
    }

    // MARK: - Active

    private func activeContent(_ session: StudySession) -> some View {
        Section {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Session Active")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text(viewModel.formattedCountdown)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                participantRoster(session)

                if session.status == .active, viewModel.isInLobby {
                    stateControls
                }

                if viewModel.isHost {
                    Button(role: .destructive) {
                        Task { await viewModel.endSession() }
                    } label: {
                        Label("End Session", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSubmitting)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var stateControls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.updateMyState(.focused) }
            } label: {
                Label("Focused", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.myState == .focused ? .green : .green.opacity(0.5))

            Button {
                Task { await viewModel.updateMyState(.break) }
            } label: {
                Label("Break", systemImage: "cup.and.saucer.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.myState == .break ? .orange : .secondary)
        }
    }

    // MARK: - Roster

    private func participantRoster(_ session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Participants (\(session.participants.count))")
                .font(.subheadline.bold())

            ForEach(session.participantList) { participant in
                HStack(spacing: 10) {
                    Image(systemName: participant.state.systemImage)
                        .foregroundStyle(color(for: participant.state))

                    Text(memberNames[participant.id] ?? "Member")
                        .font(.body)

                    if participant.id == session.hostUid {
                        Text("Host")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }

                    Spacer()

                    Text(participant.state.label)
                        .font(.caption)
                        .foregroundStyle(color(for: participant.state))
                }
            }
        }
    }

    private func color(for state: ParticipantState) -> Color {
        switch state {
        case .focused: return .green
        case .break: return .orange
        case .left: return .yellow
        case .opened: return .red
        }
    }
}

#Preview {
    List {
        SessionView(
            viewModel: SessionViewModel(),
            memberNames: ["u1": "Alex", "u2": "Jordan"]
        )
    }
}
