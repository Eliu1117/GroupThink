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

                // GRO-40: back-to-back cycle indicator.
                if session.isPomodoroCycle {
                    Label("Pomodoro cycle: \(session.totalSessionsInCycle) sessions back-to-back", systemImage: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

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
            Button {
                Task { await viewModel.endSession() }
            } label: {
                Label("Cancel Session", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kawaiiDestructive(isDisabled: viewModel.isSubmitting))
            .disabled(viewModel.isSubmitting)
        }
    }

    // MARK: - Break vote (GRO-11)

    @ViewBuilder
    private func breakVoteControls(_ session: StudySession) -> some View {
        // GRO-39: a passed vote now ends the session immediately instead of starting a break.
        if let vote = session.activeBreakVote, vote.isPending {
            // Vote in flight — show a tap-to-view banner.
            Button {
                viewModel.showBreakVoteSheet = true
            } label: {
                HStack {
                    Image(systemName: "figure.stand.line.dotted.figure.stand")
                        .foregroundStyle(Color.theme.text)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("End-early vote in progress")
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
                    Label("Vote to End Early", systemImage: "figure.stand.line.dotted.figure.stand")
                        .frame(maxWidth: .infinity)
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
        // GRO-45: voting is now scoped per sub-session block; breaks between sessions simply
        // hide these controls entirely (see `activeContent`), so no "penalty locked" case here.
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
                        // GRO-40: Break countdown — replaces the focus timer between sub-sessions.
                        breakTimerCard(session)
                    } else {
                        // GRO-19: Focus countdown — survives navigation pushes via SessionViewModel.
                        VStack(spacing: 8) {
                            Text("Session Active")
                                .font(.theme.headline())
                                .foregroundStyle(Color.theme.text)

                                // GRO-40: back-to-back cycle progress.
                                if session.isPomodoroCycle {
                                    Text(session.cycleProgressLabel)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
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

                // Hide break vote controls while a break is running.
                if viewModel.isInLobby {
                    if viewModel.isHost {
                        endEarlyButton(session)
                    }

                    if !viewModel.isOnBreak {
                        // GRO-11: Break voting controls
                        breakVoteControls(session)
                    }
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

    // MARK: - End early (matches solo Home stop button)

    private func endEarlyButton(_ session: StudySession) -> some View {
        Button {
            Task { await viewModel.endCycleEarly() }
        } label: {
            Label(endEarlyButtonTitle(session), systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.kawaiiDestructive(isDisabled: viewModel.isSubmitting))
        .disabled(viewModel.isSubmitting)
    }

    private func endEarlyButtonTitle(_ session: StudySession) -> String {
        if session.isPomodoroCycle {
            return "End Cycle Early"
        }
        if viewModel.isOnBreak {
            return "End Break"
        }
        return "End Session"
    }

    // MARK: - Break timer card (GRO-35 / GRO-40)

    /// GRO-40: breaks are now exclusively the automatic inter-session pauses in a
    /// back-to-back cycle, so `isLongBreak` reflects the Pomodoro "every 4th break" rule.
    private func isLongBreak(_ session: StudySession) -> Bool {
        PomodoroBreakCalculator.isLongBreak(
            afterSessionIndex: session.currentSessionIndex,
            configuration: session.pomodoroConfiguration
        )
    }

    private func breakTimerCard(_ session: StudySession) -> some View {
        let longBreak = isLongBreak(session)
        let breakAccent = viewModel.isBreakPaused ? Color.theme.text.opacity(0.55) : Color.theme.forestGreen

        return VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Label(longBreak ? "Long Break" : "Break Time", systemImage: "cup.and.saucer.fill")
                    .font(.theme.headline())
                    .foregroundStyle(breakAccent)

                if viewModel.isBreakPaused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.theme.caption())
                        .foregroundStyle(Color.theme.text.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.theme.surface, in: Capsule())
                }

                if session.isPomodoroCycle && session.hasMoreSessionsInCycle {
                    Text("Up next: Session \(session.currentSessionIndex + 1) of \(session.totalSessionsInCycle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Countdown
            Text(viewModel.formattedBreakCountdown)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(viewModel.isBreakPaused ? Color.theme.text.opacity(0.5) : Color.theme.text)

            Text(viewModel.isBreakPaused ? "Host has paused the break." : "Apps are unblocked! Enjoy your break.")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.6))
                .multilineTextAlignment(.center)

            // Host-only controls
            if viewModel.isHost {
                HStack(spacing: 12) {
                    breakControlButton(
                        title: viewModel.isBreakPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isBreakPaused ? "play.fill" : "pause.fill"
                    ) {
                        Task {
                            if viewModel.isBreakPaused {
                                await viewModel.resumeBreak()
                            } else {
                                await viewModel.pauseBreak()
                            }
                        }
                    }

                    breakControlButton(title: "Skip Break", systemImage: "forward.fill") {
                        Task { await viewModel.endBreakEarly() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.theme.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func breakControlButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.kawaiiOutlined)
        .disabled(viewModel.isSubmitting)
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