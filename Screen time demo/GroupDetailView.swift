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
    /// GRO-40: Pomodoro cycle settings for the NEXT session start.
    @State private var pomodoroModeEnabled = false
    @State private var totalSessionsInCycle = PomodoroConfiguration.defaultSessionCount
    @State private var pomodoroConfiguration = PomodoroConfiguration.defaults

    /// Preset durations shown in the session-start picker (minutes).
    // TODO: remove the "1" preset — added only for quick testing of session-end/cycle flows.
    private static let durationPresets = [1, 10, 15, 20, 25, 30, 45, 60, 90]
    private static let sessionStartWheelHeight: CGFloat = 110
    private static let sessionStartWheelFontSize: CGFloat = 18

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
            .tint(Color.theme.primary)
            .listRowBackground(Color.clear)
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
        .kawaiiListBackground()
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
                sessionStartCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            } footer: {
                if !canStartSession {
                    Text("Only the group creator can start a session.")
                } else if sessionDurationMin == 0 {
                    Text("Choose a session length to start.")
                } else if currentGroup.strictMode {
                    Text("Strict mode is on: all apps will be blocked except each member's whitelist.")
                } else if pomodoroModeEnabled {
                    Text(pomodoroStartFooter)
                } else {
                    Text("Host a \(sessionDurationMin.durationPhrase) focused session for this group.")
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

    // MARK: - Session start card

    private var sessionStartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if canStartSession {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Session Length", systemImage: "clock.fill")
                        .font(.theme.body())
                        .foregroundStyle(Color.theme.text)

                    DurationWheelPicker(
                        totalMinutes: $sessionDurationMin,
                        wheelHeight: Self.sessionStartWheelHeight,
                        valueFontSize: Self.sessionStartWheelFontSize
                    )
                }

                pomodoroModeSection
            }

            Button {
                Task {
                    await sessionViewModel.createSession(
                        durationMin: sessionDurationMin,
                        totalSessionsInCycle: pomodoroModeEnabled ? totalSessionsInCycle : 1,
                        pomodoroConfiguration: pomodoroConfiguration
                    )
                }
            } label: {
                Label(
                    pomodoroModeEnabled ? "Start Pomodoro Cycle" : "Start Study Hall",
                    systemImage: "play.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kawaiiPrimary(isDisabled: !canStartSession || sessionViewModel.isSubmitting || sessionDurationMin == 0))
            .disabled(!canStartSession || sessionViewModel.isSubmitting || sessionDurationMin == 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    // MARK: - Pomodoro mode (GRO-40)

    private var pomodoroModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $pomodoroModeEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pomodoro Mode")
                        .font(.theme.body())
                        .foregroundStyle(Color.theme.text)
                    Text("Run multiple focus sessions with automatic breaks in between.")
                        .font(.theme.caption())
                        .foregroundStyle(Color.theme.text.opacity(0.55))
                }
            }
            .toggleStyle(.kawaii)

            if pomodoroModeEnabled {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Consecutive Sessions")
                            .font(.theme.body())
                            .foregroundStyle(Color.theme.text)
                        Text("\(totalSessionsInCycle) focus blocks back-to-back — the group stays synced until the cycle finishes.")
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                        WheelIntPicker(
                            value: $totalSessionsInCycle,
                            range: 2...100,
                            suffix: "sessions",
                            wheelHeight: Self.sessionStartWheelHeight,
                            valueFontSize: Self.sessionStartWheelFontSize
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Break Length")
                            .font(.theme.body())
                            .foregroundStyle(Color.theme.text)
                        Text("\(pomodoroConfiguration.standardBreakMin.durationPhrase) between each session.")
                            .font(.theme.caption())
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                        WheelIntPicker(
                            value: $pomodoroConfiguration.standardBreakMin,
                            range: 1...60,
                            suffix: "min",
                            wheelHeight: Self.sessionStartWheelHeight,
                            valueFontSize: Self.sessionStartWheelFontSize
                        )
                    }

                    Toggle(isOn: $pomodoroConfiguration.longBreakEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Longer Breaks")
                                .font(.theme.body())
                                .foregroundStyle(Color.theme.text)
                            Text("Give extra recovery time on selected breaks.")
                                .font(.theme.caption())
                                .foregroundStyle(Color.theme.text.opacity(0.55))
                        }
                    }
                    .toggleStyle(.kawaii)

                    if pomodoroConfiguration.longBreakEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Long Break Every")
                                .font(.theme.body())
                                .foregroundStyle(Color.theme.text)
                            Text("Every \(pomodoroConfiguration.longBreakEveryN) sessions, the break is longer.")
                                .font(.theme.caption())
                                .foregroundStyle(Color.theme.text.opacity(0.55))
                            WheelIntPicker(
                                value: $pomodoroConfiguration.longBreakEveryN,
                                range: 2...10,
                                suffix: "sessions",
                                wheelHeight: Self.sessionStartWheelHeight,
                                valueFontSize: Self.sessionStartWheelFontSize
                            )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Long Break Length")
                                .font(.theme.body())
                                .foregroundStyle(Color.theme.text)
                            Text("\(pomodoroConfiguration.longBreakMin.durationPhrase) on long breaks.")
                                .font(.theme.caption())
                                .foregroundStyle(Color.theme.text.opacity(0.55))
                            WheelIntPicker(
                                value: $pomodoroConfiguration.longBreakMin,
                                range: 1...90,
                                suffix: "min",
                                wheelHeight: Self.sessionStartWheelHeight,
                                valueFontSize: Self.sessionStartWheelFontSize
                            )
                        }
                    }
                }
            }
        }
    }

    private var pomodoroStartFooter: String {
        var parts = [
            "Host \(totalSessionsInCycle) back-to-back \(sessionDurationMin.durationPhrase) sessions with \(pomodoroConfiguration.standardBreakMin.durationPhrase) breaks."
        ]
        if pomodoroConfiguration.longBreakEnabled {
            parts.append(
                "Every \(pomodoroConfiguration.longBreakEveryN) sessions, the break is \(pomodoroConfiguration.longBreakMin.durationPhrase)."
            )
        }
        return parts.joined(separator: " ")
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
                        .foregroundStyle(Color.theme.text.opacity(0.35))
                    Text("No Schedules Active")
                        .font(.theme.headline())
                        .foregroundStyle(Color.theme.text)
                    Text("Open a card below to enable and configure Downtime or Routines for your group.")
                        .font(.theme.body())
                        .foregroundStyle(Color.theme.text.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .listRowBackground(Color.clear)
        }

        // ── Downtime card ─────────────────────────────────────────────
        Section {
            KawaiiListRow(
                icon: "moon.stars.fill",
                iconTint: currentGroup.downtimeEnabled ? Color.theme.secondary : Color.theme.text.opacity(0.15),
                title: currentGroup.downtimeEnabled ? "Downtime · ON" : "Downtime",
                subtitle: "Nightly app-blocking window with peer overrides"
            ) {
                showDowntimeConfig = true
            }
        } footer: {
            Text(currentGroup.downtimeEnabled
                 ? "Enabled · tap to configure your personal window and manage overrides."
                 : "Disabled · tap to enable for your group and configure your personal window.")
        }

        // ── Routines card ─────────────────────────────────────────────
        Section {
            KawaiiListRow(
                icon: "sun.and.horizon.fill",
                iconTint: currentGroup.routineEnabled ? Color.theme.primary : Color.theme.text.opacity(0.15),
                title: currentGroup.routineEnabled ? "Routines · ON" : "Routines",
                subtitle: "Apps stay locked until your routine condition is met"
            ) {
                showRoutineConfig = true
            }
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
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text)
            }
            .tint(Color.theme.primary)
            .disabled(viewModel.isUpdatingSettings)
        } else {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text)
                Spacer()
                Image(systemName: value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(value ? Color.theme.secondary : Color.theme.text.opacity(0.3))
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
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text)
            }
        }
    }

    // MARK: - Invite code

    private var inviteCodeSection: some View {
        Section("Invite code") {
            HStack {
                Text(currentGroup.inviteCode)
                    .font(.system(.title2, design: .rounded).monospaced().bold())
                    .foregroundStyle(Color.theme.text)

                Spacer()

                Button {
                    UIPasteboard.general.string = currentGroup.inviteCode
                    didCopyCode = true
                } label: {
                    Label(didCopyCode ? "Copied" : "Copy", systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .tint(Color.theme.primary)
                .accessibilityLabel("Copy invite code")
            }

            Text("Share this code so friends can join your study hall.")
                .font(.theme.caption())
                .foregroundStyle(Color.theme.text.opacity(0.55))
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
                        ZStack {
                            Circle()
                                .fill(Color.theme.primary.opacity(0.35))
                                .frame(width: 30, height: 30)
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundStyle(Color.theme.text)
                        }

                        Text(member.displayName)
                            .font(.theme.body())
                            .foregroundStyle(Color.theme.text)

                        if member.id == currentGroup.createdBy {
                            Text("Creator")
                                .font(.theme.caption(10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.theme.secondary.opacity(0.5), in: Capsule())
                                .foregroundStyle(Color.theme.text)
                        }

                        if member.id == currentUserUID {
                            Text("You")
                                .font(.theme.caption())
                                .foregroundStyle(Color.theme.text.opacity(0.5))
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
            .tint(.red)
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
