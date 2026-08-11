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
                    .font(.theme.headline())
                    .foregroundStyle(Color.theme.text)

                Text("\(session.durationMin)-minute session · waiting to start")
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text.opacity(0.6))

                if session.strictMode {
                    Label("Strict mode: all apps blocked except your whitelist", systemImage: "lock.shield.fill")
                        .font(.theme.caption())
                        .foregroundStyle(Color.theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.theme.primary.opacity(0.4), in: Capsule())
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
            }
            .buttonStyle(.kawaiiPrimary(isDisabled: viewModel.isSubmitting))
            .disabled(viewModel.isSubmitting)
        }

        if viewModel.isHost {
            Button {
                Task { await viewModel.launchSession() }
            } label: {
                Label("Launch Session", systemImage: "play.fill")
            }
            .buttonStyle(.kawaiiPrimary(isDisabled: viewModel.isSubmitting || session.participants.isEmpty))
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
                        .foregroundStyle(Color.theme.text)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Break vote in progress")
                            .font(.theme.body())
                            .foregroundStyle(Color.theme.text)
                        Text("Tap to vote · \(vote.secondsRemaining)s remaining")
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.theme.text.opacity(0.35))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .background(Color.theme.primary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        } else if session.breakVotingEnabled {
            // Show the initiate button (with context-sensitive disabled reason).
            VStack(spacing: 6) {
                Button {
                    Task { await viewModel.initiateBreakVote() }
                } label: {
                    Label("Initiate Break Vote", systemImage: "figure.stand.line.dotted.figure.stand")
                }
                .buttonStyle(.kawaiiOutlined)
                .disabled(!session.canInitiateBreakVote || viewModel.isSubmitting)

                if let reason = breakVoteDisabledReason(session) {
                    Text(reason)
                        .font(.theme.caption())
                        .foregroundStyle(Color.theme.text.opacity(0.55))
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
                                .font(.theme.headline())
                                .foregroundStyle(Color.theme.text)
                            Text(viewModel.formattedCountdown)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.theme.text)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.theme.primary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    // Banner for observers / late-joiners who haven't joined yet.
                    VStack(spacing: 8) {
                        Text("Session In Progress")
                            .font(.theme.headline())
                            .foregroundStyle(Color.theme.text)
                        Text("\(session.durationMin)-minute session · in progress")
                            .font(.theme.body())
                            .foregroundStyle(Color.theme.text.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.theme.primary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
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
                    }
                    .buttonStyle(.kawaiiPrimary(isDisabled: viewModel.isSubmitting))
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
                    .font(.theme.headline())
                    .foregroundStyle(Color.theme.text)

                if viewModel.isBreakPaused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.theme.caption())
                        .foregroundStyle(Color.theme.text.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.theme.surface, in: Capsule())
                }
            }

            // Countdown
            Text(viewModel.formattedBreakCountdown)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(viewModel.isBreakPaused ? Color.theme.text.opacity(0.5) : Color.theme.text)

            Text(viewModel.isBreakPaused ? "Host has paused the break." : "Shields are down — enjoy your break!")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.6))
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
                    }
                    .buttonStyle(.kawaiiOutlined)
                    .disabled(viewModel.isSubmitting)

                    // End break early
                    Button(role: .destructive) {
                        Task { await viewModel.endSession() }
                    } label: {
                        Label("End Break", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(viewModel.isSubmitting)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.theme.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
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
