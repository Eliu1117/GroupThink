//
//  SessionSectionView.swift
//  Screen time demo
//
//  The live study-hall UI, rendered as List sections inside GroupDetailView.
//

import SwiftUI

struct SessionSectionView: View {
    @ObservedObject var session: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var durationMin = 25

    var body: some View {
        Group {
            if let current = session.session {
                switch current.status {
                case .lobby:
                    lobbySections(current)
                case .active:
                    activeSections(current)
                case .ended:
                    startSection
                }
            } else {
                startSection
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhase(newPhase)
        }
    }

    // MARK: - No session: start one

    private var startSection: some View {
        Section("Study hall") {
            Picker("Duration", selection: $durationMin) {
                ForEach([10, 15, 25, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
            }
            Button {
                Task { await session.createSession(durationMin: durationMin) }
            } label: {
                Label("Start a study hall", systemImage: "play.circle.fill")
            }
            .disabled(session.isWorking)
        }
    }

    // MARK: - Lobby

    private func lobbySections(_ current: StudySession) -> some View {
        Group {
            Section("Lobby") {
                Label("\(current.durationMin) minute session", systemImage: "timer")
                Label("\(current.blockedAppCount) apps blocked by host", systemImage: "lock.fill")

                if !session.isParticipant {
                    Button {
                        Task { await session.joinSession() }
                    } label: {
                        Label("Join lobby", systemImage: "person.badge.plus")
                    }
                    .disabled(session.isWorking)
                }

                if session.isHost {
                    Button {
                        Task { await session.activateSession() }
                    } label: {
                        Label("Start now — block apps", systemImage: "lock.shield.fill")
                    }
                    .disabled(session.isWorking)

                    Button(role: .destructive) {
                        Task { await session.endSession() }
                    } label: {
                        Label("Cancel session", systemImage: "xmark.circle")
                    }
                }
            }
            participantsSection(current, title: "In the lobby")
        }
    }

    // MARK: - Active

    private func activeSections(_ current: StudySession) -> some View {
        Group {
            Section {
                VStack(spacing: 8) {
                    Text("Focusing")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(formattedTime(session.timeRemaining))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            participantsSection(current, title: "Who's focusing")

            Section {
                if session.isHost {
                    Button(role: .destructive) {
                        Task { await session.endSession() }
                    } label: {
                        Label("End session for everyone", systemImage: "stop.circle.fill")
                    }
                } else if session.myState == .focused {
                    Button(role: .destructive) {
                        Task { await session.leaveEarly() }
                    } label: {
                        Label("Leave early", systemImage: "figure.walk.departure")
                    }
                }
            } footer: {
                Text("Leaving early or opening a blocked app is visible to your whole group.")
            }
        }
    }

    // MARK: - Shared

    private func participantsSection(_ current: StudySession, title: String) -> some View {
        Section(title) {
            ForEach(current.sortedParticipants, id: \.uid) { entry in
                ParticipantRow(
                    info: entry.info,
                    isHost: entry.uid == current.hostUid,
                    isYou: entry.uid == session.myUid
                )
            }
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
