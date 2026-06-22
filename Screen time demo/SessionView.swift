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

            // GRO-34: cancel before launch — no summary shown because startAt is nil.
            Button(role: .destructive) {
                Task { await viewModel.endSession() }
            } label: {
                Label("Cancel Session", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(viewModel.isSubmitting)
        }
    }

    // MARK: - Break vote (GRO-11)

    @ViewBuilder
    private func breakVoteControls(_ session: StudySession) -> some View {
        if let vote = session.activeBreakVote, vote.isPending {
            // Vote in flight — show a tap-to-view banner.
            Button {
                viewModel.showBreakVoteSheet = true
            } label: {
                HStack {
                    Image(systemName: "figure.stand.line.dotted.figure.stand")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Break vote in progress")
                            .font(.subheadline.weight(.semibold))
                        Text("Tap to vote · \(vote.secondsRemaining)s remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else if session.breakVotingEnabled {
            // Show the initiate button (with context-sensitive disabled reason).
            VStack(spacing: 6) {
                Button {
                    Task { await viewModel.initiateBreakVote() }
                } label: {
                    Label("Initiate Break Vote", systemImage: "figure.stand.line.dotted.figure.stand")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(!session.canInitiateBreakVote || viewModel.isSubmitting)

                if let reason = breakVoteDisabledReason(session) {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func breakVoteDisabledReason(_ session: StudySession) -> String? {
        guard session.breakVotingEnabled else { return nil }
        if session.penaltyLock {
            return "A break already passed this session — voting is locked."
        }
        if !session.breakTimeLockCleared {
            let needed = session.durationMin / 2
            return "Break votes unlock after \(needed) min of focus."
        }
        if !session.breakCooldownCleared {
            let mins = session.breakCooldownMinutes
            return "Cooldown active — you can vote again every \(mins) min."
        }
        if session.activeBreakVote != nil {
            return "A vote is already in progress."
        }
        return nil
    }

    // MARK: - Active

    private func activeContent(_ session: StudySession) -> some View {
        Section {
            VStack(spacing: 20) {
                if viewModel.isInLobby {
                    if viewModel.isOnBreak {
                        // GRO-11: Break countdown — replaces the focus timer while the break runs.
                        breakTimerCard
                    } else {
                        // GRO-19: Focus countdown — survives navigation pushes via SessionViewModel.
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
                    }
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

                // GRO-18: Roster
                FocusRosterView(
                    participants: viewModel.participants,
                    memberNames: memberNames,
                    hostUid: session.hostUid
                )

                // Hide end-session / break vote controls while a break is running.
                if viewModel.isInLobby, !viewModel.isOnBreak {
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

                    // GRO-11: Break voting controls
                    breakVoteControls(session)
                }

                // GRO-14: Late-join button
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

    // MARK: - Break timer card (GRO-35)

    private var breakTimerCard: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Label("Break Time", systemImage: "cup.and.saucer.fill")
                    .font(.headline)
                    .foregroundStyle(viewModel.isBreakPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))

                if viewModel.isBreakPaused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            // Countdown
            Text(viewModel.formattedBreakCountdown)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(viewModel.isBreakPaused ? .secondary : .primary)

            Text(viewModel.isBreakPaused ? "Host has paused the break." : "Shields are down — enjoy your break!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Host-only controls
            if viewModel.isHost {
                HStack(spacing: 12) {
                    // Pause / Resume
                    Button {
                        Task {
                            if viewModel.isBreakPaused {
                                await viewModel.resumeBreak()
                            } else {
                                await viewModel.pauseBreak()
                            }
                        }
                    } label: {
                        Label(
                            viewModel.isBreakPaused ? "Resume" : "Pause",
                            systemImage: viewModel.isBreakPaused ? "play.fill" : "pause.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.isBreakPaused ? .green : .orange)
                    .disabled(viewModel.isSubmitting)

                    // End break early
                    Button(role: .destructive) {
                        Task { await viewModel.endSession() }
                    } label: {
                        Label("End Break", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSubmitting)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            (viewModel.isBreakPaused ? Color.secondary : Color.green).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12)
        )
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
