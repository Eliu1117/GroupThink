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
    /// Subscribing here forces this screen's `body` to re-run on theme change — see the
    /// comment on `ContentView`'s equivalent property for why this is needed.
    @EnvironmentObject private var themeSettings: ThemeSettings
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
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                tallyCard

                if let vote {
                    switch vote.status {
                    case .pending:
                        votingSection
                    case .passed:
                        // GRO-39: a passed vote ends the current sub-session; in a
                        // back-to-back cycle that just moves on to the regular break.
                        resultBanner(
                            icon: "checkmark.circle.fill",
                            text: viewModel.session?.hasMoreSessionsInCycle == true
                                ? "Vote passed! Wrapping up this session early."
                                : "Vote passed! Ending the session now.",
                            color: Color.theme.forestGreen
                        )
                    case .failed, .expired:
                        resultBanner(
                            icon: "xmark.circle.fill",
                            text: "Vote didn't pass. Stay focused!",
                            color: Color.theme.primary
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .kawaiiBackground()
        .navigationTitle("Break Vote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Dismiss") {
                    viewModel.showBreakVoteSheet = false
                }
                .tint(Color.theme.text)
                .disabled(vote?.isPending == true)
            }
        }
        .onAppear { syncCountdown() }
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            syncCountdown()
        }
        // Explicitly *reading* `themeSettings.theme` guarantees repaint on theme change.
        .animation(.easeInOut(duration: 0.2), value: themeSettings.theme)
    }

    // MARK: - Header + countdown

    private var initiatorName: String {
        if let vote, let name = viewModel.participantNames[vote.initiatorUid] { return name }
        return "A member"
    }

    private var headerCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("\(initiatorName) wants to end early")
                    .font(.theme.heading(20))
                    .foregroundStyle(Color.theme.text)
                    .multilineTextAlignment(.center)
                Text("Everyone gets a say. Cast your vote before time runs out.")
                    .font(.theme.caption(13))
                    .foregroundStyle(Color.theme.text.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            ZStack {
                Circle()
                    .stroke(Color.theme.secondary.opacity(0.35), lineWidth: 12)

                Circle()
                    .trim(
                        from: 0,
                        to: vote.map { CGFloat(voteSecondsRemaining) / CGFloat(max(1, $0.windowSeconds)) } ?? 0
                    )
                    .stroke(
                        timerColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    // GRO-29: only animate while ticking; initial value is pre-seeded.
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
            .frame(width: 170, height: 170)
        }
        .frame(maxWidth: .infinity)
        .kawaiiCard(padding: 20)
    }

    // MARK: - Tally

    private var tallyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(yesCount) to end early", systemImage: "hand.thumbsup.fill")
                    .font(.theme.headline(15))
                    .foregroundStyle(Color.theme.forestGreen)
                Spacer()
                Text("Need \(neededForPass)")
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.theme.secondary.opacity(0.25), in: Capsule())
            }

            GeometryReader { geo in
                let fraction = CGFloat(yesCount) / CGFloat(max(1, totalParticipants))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.secondary.opacity(0.3))
                    Capsule()
                        .fill(Color.theme.forestGreen)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                        .animation(.spring(duration: 0.4), value: yesCount)
                }
            }
            .frame(height: 10)

            Text("\(votedCount) of \(totalParticipants) voted")
                .font(.theme.caption())
                .foregroundStyle(Color.theme.text.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kawaiiCard()
    }

    // MARK: - Voting

    @ViewBuilder
    private var votingSection: some View {
        if let myVote {
            HStack(spacing: 10) {
                Image(systemName: myVote ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                Text(myVote ? "You voted: End early" : "You voted: Keep going")
                    .font(.theme.headline(15))
            }
            .foregroundStyle(Color.theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.theme.secondary.opacity(0.3), in: Capsule())
        } else {
            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.castBreakVote(inFavor: true) }
                } label: {
                    Label("End Early", systemImage: "hand.thumbsup.fill")
                }
                .buttonStyle(.kawaiiPrimary())

                Button {
                    Task { await viewModel.castBreakVote(inFavor: false) }
                } label: {
                    Label("Keep Going", systemImage: "hand.thumbsdown.fill")
                }
                .buttonStyle(.kawaiiOutlined)
            }
        }
    }

    // MARK: - Result banner

    private func resultBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
            Text(text)
                .font(.theme.headline(15))
                .foregroundStyle(Color.theme.text)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Helpers

    private var timerColor: Color {
        guard let vote, vote.windowSeconds > 0 else { return Color.theme.primary }
        let fraction = Double(voteSecondsRemaining) / Double(vote.windowSeconds)
        return fraction > 0.25 ? Color.theme.primary : Color.red.opacity(0.85)
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
