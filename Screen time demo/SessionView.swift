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

                if session.strictMode {
                    Label("Strict mode: all apps blocked except your whitelist", systemImage: "lock.shield.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.purple.opacity(0.1), in: Capsule())
                }

                // GRO-18: Renamed FocusRosterView
                FocusRosterView(
                    participants: viewModel.participants,
                    memberNames: memberNames,
                    hostUid: session.hostUid
                )

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
                if viewModel.isInLobby {
                    // Countdown for participants who are already in the session.
                    VStack(spacing: 8) {
                        Text("Session Active")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        // GRO-19: secondsRemaining is driven by the long-lived countdown
                        // task in SessionViewModel, so it survives navigation pushes.
                        Text(viewModel.formattedCountdown)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    // Banner for observers / late-joiners who haven't joined yet.
                    VStack(spacing: 8) {
                        Text("Session In Progress")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Text("\(session.durationMin)-minute session · in progress")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                // GRO-18: Renamed FocusRosterView
                FocusRosterView(
                    participants: viewModel.participants,
                    memberNames: memberNames,
                    hostUid: session.hostUid
                )

                if viewModel.isInLobby, viewModel.isHost {
                    Button(role: .destructive) {
                        Task { await viewModel.endSession() }
                    } label: {
                        Label("End Session", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSubmitting)
                }

                // GRO-14: Late-join button shown when the session is active,
                // the user is not yet a participant, and the group allows late joining.
                if viewModel.canLateJoin {
                    Button {
                        Task { await viewModel.joinLobby() }
                    } label: {
                        Label("Join Active Session", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(viewModel.isSubmitting)
                }
            }
            .padding(.vertical, 4)
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
