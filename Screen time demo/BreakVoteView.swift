//
//  BreakVoteView.swift
//  Screen time demo
//
//  Bottom sheet rendered when an active break vote is in flight.
//  Presented from GroupDetailView inside a NavigationStack — this view must NOT
//  wrap itself in another NavigationStack or the navigation bar title will render
//  twice, causing the title to overlap the content (GRO-29).
//

import Combine
import SwiftUI

struct BreakVoteView: View {
    @ObservedObject var viewModel: SessionViewModel
    let currentUID: String?

    // GRO-29: pre-seed to the correct value so the circle arc never animates from 0.
    @State private var voteSecondsRemaining: Int

    private var vote: BreakVote? { viewModel.session?.activeBreakVote }
    private var totalParticipants: Int { viewModel.session?.participants.count ?? 1 }

    private var myVote: Bool? {
        guard let vote, let uid = currentUID else { return nil }
        return vote.votes[uid]
    }

    private var yesCount: Int { vote?.votes.values.filter { $0 }.count ?? 0 }
    private var votedCount: Int { vote?.votes.count ?? 0 }
    private var neededForPass: Int {
        max(1, Int(ceil(Double(totalParticipants) * 0.67)))
    }

    // GRO-29: custom init pre-seeds the countdown so the circle renders at the correct position
    // on first frame, avoiding the animated sweep from 0 to the actual value.
    init(viewModel: SessionViewModel, currentUID: String?) {
        self.viewModel = viewModel
        self.currentUID = currentUID
        self._voteSecondsRemaining = State(
            initialValue: viewModel.session?.activeBreakVote?.secondsRemaining ?? 0
        )
    }

    // GRO-29: No inner NavigationStack — the presenting sheet in GroupDetailView already
    // wraps this view in one. Adding a second NavigationStack causes a double nav bar
    // which renders the title on top of the content below.
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            countdownSection
            tallySection

            if let vote {
                switch vote.status {
                case .pending:
                    votingButtons(vote: vote)
                case .passed:
                    resultBanner(text: "Break approved! 🎉 Shields are down.", color: .green)
                case .failed, .expired:
                    resultBanner(text: "Vote didn't pass. Stay focused!", color: .orange)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .kawaiiBackground()
        .navigationTitle("Break Vote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Dismiss") {
                    viewModel.showBreakVoteSheet = false
                }
                .disabled(vote?.isPending == true)
            }
        }
        .onAppear { syncCountdown() }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            syncCountdown()
        }
    }

    // MARK: - Header

    // GRO-29: removed the outer VStack wrapper that was inside a NavigationStack header —
    // content now stacks cleanly below the inline nav title without overlap.
    // @ViewBuilder avoids a naming collision with the app's Group data model (SwiftUI.Group
    // would be ambiguous in this context).
    @ViewBuilder
    private var headerSection: some View {
        if let vote, let name = viewModel.participantNames[vote.initiatorUid] {
            Text("\(name) wants a break")
                .font(.theme.heading(20))
                .foregroundStyle(Color.theme.text)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        } else {
            Text("A member wants a break")
                .font(.theme.heading(20))
                .foregroundStyle(Color.theme.text)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }

    // MARK: - Countdown circle

    private var countdownSection: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 10)

            Circle()
                .trim(
                    from: 0,
                    to: vote.map { CGFloat(voteSecondsRemaining) / CGFloat(max(1, $0.windowSeconds)) } ?? 0
                )
                .stroke(
                    timerColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // GRO-29: animate only when ticking — the initial value is pre-seeded in init
                // so there is no 0→value sweep when the sheet first appears.
                .animation(.linear(duration: 1), value: voteSecondsRemaining)

            VStack(spacing: 2) {
                Text(formattedCountdown)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.theme.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("remaining")
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.55))
            }
        }
        .frame(width: 160, height: 160)
    }

    // MARK: - Tally

    private var tallySection: some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(yesCount) for a break", systemImage: "hand.thumbsup.fill")
                    .font(.theme.body())
                    .foregroundStyle(Color(hex: "6FA287"))
                Spacer()
                Text("Need \(neededForPass) to pass")
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.55))
            }
            ProgressView(value: Double(yesCount), total: Double(totalParticipants))
                .tint(.green)

            HStack {
                Text("\(votedCount) of \(totalParticipants) voted")
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.55))
                Spacer()
            }
        }
        .kawaiiCard()
    }

    // MARK: - Voting buttons

    @ViewBuilder
    private func votingButtons(vote: BreakVote) -> some View {
        if let myVote {
            Label(
                myVote ? "You voted: For a break" : "You voted: Against",
                systemImage: myVote ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(myVote ? .green : .orange)
            .padding()
            .background(
                (myVote ? Color.green : Color.orange).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 10)
            )
        } else {
            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.castBreakVote(inFavor: false) }
                } label: {
                    Label("Against", systemImage: "hand.thumbsdown.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    Task { await viewModel.castBreakVote(inFavor: true) }
                } label: {
                    Label("For Break", systemImage: "hand.thumbsup.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    // MARK: - Result banner

    private func resultBanner(text: String, color: Color) -> some View {
        Text(text)
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private var timerColor: Color {
        guard let vote, vote.windowSeconds > 0 else { return .blue }
        let fraction = Double(voteSecondsRemaining) / Double(vote.windowSeconds)
        return fraction > 0.4 ? .blue : (fraction > 0.2 ? .orange : .red)
    }

    private var formattedCountdown: String {
        let m = voteSecondsRemaining / 60
        let s = voteSecondsRemaining % 60
        return String(format: "%d:%02d", m, s)
    }

    private func syncCountdown() {
        guard let vote else { return }
        voteSecondsRemaining = vote.secondsRemaining
    }
}
