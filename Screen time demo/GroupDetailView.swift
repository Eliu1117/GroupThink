//
//  GroupDetailView.swift
//  Screen time demo
//
//  GRO-31: Refactored to a three-tab layout so Study Hall session logic,
//  personal schedule configuration, and group settings are fully decoupled.
//

import SwiftUI
import UIKit

// MARK: - Tab model

enum GroupTab: String, CaseIterable {
    case studyHalls = "Study Halls"
    case schedules  = "Schedules"
    case settings   = "Settings"
}

// MARK: - View

struct GroupDetailView: View {
    let group: Group
    let currentUserUID: String?
    /// When true the view auto-starts a new session on first appearance (used after group creation).
    var autoStartSession: Bool = false

    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = GroupDetailViewModel()
    @StateObject private var sessionViewModel = SessionViewModel()

    @State private var selectedTab: GroupTab = .studyHalls
    @State private var didCopyCode = false
    @State private var showDeleteConfirmation = false
    @State private var didAutoStart = false
    /// Controls the Downtime configuration sheet (presented independently of session logic).
    @State private var showDowntimeConfig = false
    /// Controls the Routine configuration sheet.
    @State private var showRoutineConfig = false
    /// GRO-28: duration used for the NEXT session created from this screen.
    /// Seeded from currentGroup.defaultSessionDurationMin and stays in sync with live group changes.
    @State private var sessionDurationMin: Int = 25
    /// GRO-40: number of consecutive (back-to-back / Pomodoro) sessions for the NEXT cycle.
    /// 1 = a plain single session; 2+ inserts automatic breaks between sub-sessions.
    @State private var totalSessionsInCycle: Int = 1

    /// Preset durations shown in the session-start picker (minutes).
    // TODO: remove the "1" preset — added only for quick testing of session-end/cycle flows.
    private static let durationPresets = [1, 10, 15, 20, 25, 30, 45, 60, 90]

    /// Live group doc when available; falls back to the pushed snapshot.
    private var currentGroup: Group {
        viewModel.liveGroup ?? group
    }

    private var isCreator: Bool {
        guard let currentUserUID else { return false }
        return currentGroup.createdBy == currentUserUID
    }

    private var canStartSession: Bool {
        guard currentUserUID != nil else { return false }
        return !currentGroup.creatorOnlyStart || isCreator
    }

    // MARK: - Body

    var body: some View {
        List {
            // ── Segmented tab picker ─────────────────────────────────────
            Picker("", selection: $selectedTab) {
                ForEach(GroupTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color(.systemGroupedBackground))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // ── Tab content ──────────────────────────────────────────────
            switch selectedTab {
            case .studyHalls:
                studyHallsContent
            case .schedules:
                schedulesContent
            case .settings:
                settingsContent
            }
        }
        .navigationTitle(currentGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete Group?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                Task { await deleteGroup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to permanently delete this group? This action cannot be undone.")
        }
        // ── Sheets ─────────────────────────────────────────────────────
        .sheet(item: $sessionViewModel.sessionSummary) { summary in
            SessionSummaryView(summary: summary)
        }
        .sheet(isPresented: $sessionViewModel.showBreakVoteSheet) {
            NavigationStack {
                BreakVoteView(
                    viewModel: sessionViewModel,
                    currentUID: currentUserUID
                )
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDowntimeConfig) {
            NavigationStack {
                DowntimeSettingsView(
                    groupID: currentGroup.id,
                    currentUID: currentUserUID ?? "",
                    isGroupCreator: isCreator,
                    groupFeatureEnabled: currentGroup.downtimeEnabled
                )
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showRoutineConfig) {
            NavigationStack {
                RoutineSettingsView(
                    groupID: currentGroup.id,
                    currentUID: currentUserUID ?? "",
                    isGroupCreator: isCreator,
                    groupFeatureEnabled: currentGroup.routineEnabled
                )
            }
            .presentationDetents([.large])
        }
        .overlay {
            if viewModel.isDeleting || sessionViewModel.isSubmitting {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task(id: group.memberUids) {
            await authViewModel.syncProfileToFirestore()
            sessionViewModel.updateGroupSettings(group: currentGroup)

            var knownNames: [String: String] = [:]
            if let currentUserUID {
                knownNames[currentUserUID] = authViewModel.resolvedProfileDisplayName
            }
            await viewModel.loadMembers(for: group, knownNames: knownNames)
            sessionViewModel.seedParticipantNames(viewModel.memberNames)

            // GRO-28/GRO-33: seed duration picker from last session's duration.
            sessionDurationMin = currentGroup.lastSessionDurationMin

            if autoStartSession, !didAutoStart, canStartSession, sessionViewModel.session == nil {
                didAutoStart = true
                _ = await sessionViewModel.createSession(durationMin: currentGroup.lastSessionDurationMin)
            }
        }
        .onAppear {
            sessionViewModel.configure(groupID: group.id, currentUID: currentUserUID)
            viewModel.startObservingGroup(groupID: group.id)
        }
        .onChange(of: viewModel.liveGroup) { _, liveGroup in
            if let liveGroup {
                sessionViewModel.updateGroupSettings(group: liveGroup)
                // GRO-28: only sync the picker when no session is pending/active,
                // so a mid-session default change doesn't reset the in-flight duration.
                if sessionViewModel.session == nil {
                    sessionDurationMin = liveGroup.lastSessionDurationMin
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            sessionViewModel.handleScenePhase(newPhase)
        }
    }

    // MARK: - Tab: Study Halls

    @ViewBuilder
    private var studyHallsContent: some View {
        // Active / lobby session view
        if sessionViewModel.session != nil {
            SessionView(
                viewModel: sessionViewModel,
                memberNames: sessionViewModel.participantNames
            )
        }

        // Start button (only when no session is live)
        if sessionViewModel.session == nil {
            Section {
                // GRO-28: Duration preset picker — visible to anyone who can start.
                if canStartSession {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session Length")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        // Segmented picker for the most common durations.
                        Picker("Duration", selection: $sessionDurationMin) {
                            ForEach(Self.durationPresets, id: \.self) { mins in
                                Text("\(mins)m").tag(mins)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // GRO-40: back-to-back (Pomodoro) session count. 1 = single session.
                    Stepper(value: $totalSessionsInCycle, in: 1...8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Consecutive Sessions")
                                .font(.subheadline.weight(.medium))
                            Text(
                                totalSessionsInCycle > 1
                                    ? "\(totalSessionsInCycle) sessions back-to-back, with automatic breaks in between"
                                    : "Single session — no automatic break cycle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    Task {
                        await sessionViewModel.createSession(
                            durationMin: sessionDurationMin,
                            totalSessionsInCycle: totalSessionsInCycle
                        )
                    }
                } label: {
                    Label(
                        totalSessionsInCycle > 1 ? "Start Pomodoro Cycle" : "Start Study Hall",
                        systemImage: "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartSession || sessionViewModel.isSubmitting)
            } footer: {
                if !canStartSession {
                    Text("Only the group creator can start a session.")
                } else if currentGroup.strictMode {
                    Text("Strict mode is on: all apps will be blocked except each member's whitelist.")
                } else if totalSessionsInCycle > 1 {
                    Text("Host \(totalSessionsInCycle) back-to-back \(sessionDurationMin)-minute sessions, with automatic breaks between them (every 4th is a long break).")
                } else {
                    Text("Host a \(sessionDurationMin)-minute focused session for this group.")
                }
            }
        }

        // Roster — always visible in Study Halls tab
        membersSection

        // Inline error messages
        if let err = sessionViewModel.errorMessage {
            Section {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Tab: Schedules (GRO-12 / GRO-13)

    @ViewBuilder
    private var schedulesContent: some View {
        // ── Empty state ───────────────────────────────────────────────
        if !currentGroup.downtimeEnabled && !currentGroup.routineEnabled {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Schedules Active")
                        .font(.headline)
                    Text("Open a card below to enable and configure Downtime or Routines for your group.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .listRowBackground(Color.clear)
        }

        // ── Downtime card ─────────────────────────────────────────────
        Section {
            Button {
                showDowntimeConfig = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "moon.stars.fill")
                        .font(.title2)
                        .foregroundStyle(currentGroup.downtimeEnabled ? .indigo : .secondary)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Downtime")
                                .font(.headline)
                            if currentGroup.downtimeEnabled {
                                Text("ON")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.indigo.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.indigo)
                            }
                        }
                        Text("Nightly app-blocking window with peer overrides")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } footer: {
            Text(currentGroup.downtimeEnabled
                 ? "Enabled · tap to configure your personal window and manage overrides."
                 : "Disabled · tap to enable for your group and configure your personal window.")
        }

        // ── Routines card ─────────────────────────────────────────────
        Section {
            Button {
                showRoutineConfig = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.title2)
                        .foregroundStyle(currentGroup.routineEnabled ? .orange : .secondary)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Routines")
                                .font(.headline)
                            if currentGroup.routineEnabled {
                                Text("ON")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text("Apps stay locked until your routine condition is met")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } footer: {
            Text(currentGroup.routineEnabled
                 ? "Enabled · tap to configure your routine schedule."
                 : "Disabled · tap to enable for your group and configure your routine.")
        }
    }

    // MARK: - Tab: Settings

    @ViewBuilder
    private var settingsContent: some View {
        groupSettingsSection
        leaderboardSection
        inviteCodeSection

        if let err = viewModel.errorMessage {
            Section {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }

        if isCreator {
            deleteGroupSection
        }
    }

    // MARK: - Group settings section

    private var groupSettingsSection: some View {
        Section {
            settingRow(key: "strictMode",         value: currentGroup.strictMode,         title: "Strict Mode",       symbol: "lock.shield.fill")
            settingRow(key: "requireBlocklist",    value: currentGroup.requireBlocklist,    title: "Require Blocklist", symbol: "checklist")
            settingRow(key: "allowLateJoin",       value: currentGroup.allowLateJoin,       title: "Allow Late Join",   symbol: "person.badge.clock.fill")
            settingRow(key: "creatorOnlyStart",    value: currentGroup.creatorOnlyStart,    title: "Creator-Only Start",symbol: "crown.fill")
            settingRow(key: "breakVotingEnabled",  value: currentGroup.breakVotingEnabled,  title: "Break Voting",      symbol: "figure.stand.line.dotted.figure.stand")
            // GRO-33: Duration is auto-saved from the last session; no manual setting row needed.
            // GRO-32: Downtime and Routine toggles live inside the Schedules tab config sheets.
        } header: {
            Text("Session Settings")
        } footer: {
            if isCreator {
                Text("These toggles affect all session participants. Enable Downtime or Routines from the Schedules tab.")
            } else {
                Text("Only the group creator can change these settings.")
            }
        }
    }


    @ViewBuilder
    private func settingRow(key: String, value: Bool, title: String, symbol: String) -> some View {
        if isCreator {
            Toggle(isOn: settingBinding(key: key, value: value)) {
                Label(title, systemImage: symbol)
            }
            .disabled(viewModel.isUpdatingSettings)
        } else {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(value ? .green : .secondary)
            }
        }
    }

    private func settingBinding(key: String, value: Bool) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { newValue in
                guard let currentUserUID else { return }
                Task {
                    await viewModel.updateSetting(
                        groupID: group.id,
                        requesterUID: currentUserUID,
                        key: key,
                        value: newValue
                    )
                }
            }
        )
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        Section {
            NavigationLink {
                GroupLeaderboardView(
                    group: currentGroup,
                    currentUserUID: currentUserUID,
                    memberNames: viewModel.memberNames
                )
            } label: {
                Label("Leaderboard", systemImage: "trophy.fill")
            }
        }
    }

    // MARK: - Invite code

    private var inviteCodeSection: some View {
        Section("Invite code") {
            HStack {
                Text(currentGroup.inviteCode)
                    .font(.title2.monospaced().bold())

                Spacer()

                Button {
                    UIPasteboard.general.string = currentGroup.inviteCode
                    didCopyCode = true
                } label: {
                    Label(didCopyCode ? "Copied" : "Copy", systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Copy invite code")
            }

            Text("Share this code so friends can join your study hall.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Members (shown in Study Halls tab)

    private var membersSection: some View {
        Section("Members (\(currentGroup.memberUids.count))") {
            if viewModel.isLoading && viewModel.members.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                ForEach(viewModel.members) { member in
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.secondary)

                        Text(member.displayName)

                        if member.id == currentGroup.createdBy {
                            Text("Creator")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }

                        if member.id == currentUserUID {
                            Text("You")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Delete group

    private var deleteGroupSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Group", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isDeleting)
        }
    }

    private func deleteGroup() async {
        guard let currentUserUID else { return }
        sessionViewModel.stopListening()
        viewModel.stopObservingGroup()
        if await viewModel.deleteGroup(groupID: group.id, requesterUID: currentUserUID) {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GroupDetailView(
            group: Group(
                id: "preview",
                name: "Finals Crew",
                inviteCode: "K7Q2Z9",
                createdBy: "user1",
                memberUids: ["user1", "user2"]
            ),
            currentUserUID: "user1"
        )
        .environmentObject(AuthViewModel())
    }
}
