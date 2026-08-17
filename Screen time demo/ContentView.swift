//
//  ContentView.swift
//  Screen time demo
//
//  Solo focus mode: block apps for a customisable duration with optional strict mode.
//  GRO-36: duration picker (10–90 min), strict-mode toggle.
//

import FamilyControls
import SwiftUI

struct ContentView: View {
    // GRO-36: selectable durations matching the group session presets.
    // TODO: remove the "1" preset — added only for quick testing of session-end/cycle flows.
    private static let durationPresets = [1, 10, 15, 20, 25, 30, 45, 60, 90]

    @StateObject private var authManager = AuthorizationManager.shared

    @State private var selection = BlocklistStore.shared.selection
    @State private var showPicker = false
    @State private var whitelistSelection = BlocklistStore.shared.whitelistSelection
    @State private var showWhitelistPicker = false
    @State private var isBlocking = false
    @State private var timeRemaining = 0
    @State private var blockTask: Task<Void, Never>?

    // GRO-30: personal session summary
    @State private var sessionStartAt: Date?
    @State private var sessionPlannedDurationMin = 0
    @State private var sessionWasStrict = false
    @State private var personalSummary: PersonalSessionSummary?

    // GRO-36: new controls
    @State private var selectedDurationMin = 30
    @State private var strictMode = false

    private var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count
    }

    private var whitelistedCount: Int {
        whitelistSelection.applicationTokens.count
    }

    private var canStartBlock: Bool {
        guard authManager.isAuthorized, !isBlocking else { return false }
        // In strict mode a blocklist is optional (everything is blocked).
        return selectedDurationMin > 0 && (strictMode ? true : selectedCount > 0)
    }

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if isBlocking {
                    ScrollView {
                        activeSessionScreen
                            .padding()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            homeHeader
                            idleControls
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .kawaiiBackground()
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(isBlocking ? .hidden : .visible, for: .tabBar)
            .familyActivityPicker(isPresented: $showPicker, selection: $selection)
            .familyActivityPicker(isPresented: $showWhitelistPicker, selection: $whitelistSelection)
            .onChange(of: selection) { _, newValue in
                BlocklistStore.shared.selection = newValue
            }
            .onChange(of: whitelistSelection) { _, newValue in
                BlocklistStore.shared.whitelistSelection = newValue
            }
            .onAppear {
                authManager.refreshAuthorizationStatus()
            }
            .sheet(item: $personalSummary) { summary in
                PersonalSessionSummaryView(summary: summary)
            }
        }
    }

    // MARK: - Header

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Home")
                .font(.theme.heading(40))
                .foregroundStyle(Color.theme.text)

            Text("Customize your Blocklist and Whitelist here, or start an individual Focus Block session.")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleControls: some View {
        VStack(spacing: 12) {
            durationPicker
            strictModeSection
            chooseAppsButton
            whitelistSection
            startBlockButton
        }
    }

    // MARK: - Active session

    private var activeSessionScreen: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)

            VStack(spacing: 10) {
                Text("Focus Active")
                    .font(.theme.headline())
                    .foregroundStyle(Color.theme.text)

                Text(formattedTime(timeRemaining))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.theme.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Text("Add time")
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.6))

                HStack(spacing: 10) {
                    addTimeChip(minutes: 5)
                    addTimeChip(minutes: 15)
                    addTimeChip(minutes: 30)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 40)

            stopButton
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 560)
    }

    private func addTimeChip(minutes: Int) -> some View {
        Button {
            addTime(minutes: minutes)
        } label: {
            Text("+\(minutes) min")
                .font(.theme.body(14))
                .foregroundStyle(Color.theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Color.theme.text.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duration picker (GRO-36)

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Duration", systemImage: "clock.fill")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text)

            DurationWheelPicker(totalMinutes: $selectedDurationMin, isEnabled: !isBlocking)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Strict mode section (GRO-36)

    private var strictModeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $strictMode) {
                Label("Strict Mode", systemImage: "lock.shield.fill")
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text)
            }
            .toggleStyle(.kawaii)
            .disabled(isBlocking)
            if strictMode {
                Text("All apps blocked except your whitelist. A blocklist is optional.")
                    .font(.theme.caption(11))
                    .foregroundStyle(Color.theme.text.opacity(0.55))
            }
        }
        .padding(12)
        .background(Color.theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Buttons

    private var chooseAppsButton: some View {
        Button {
            showPicker = true
        } label: {
            Label(
                selectedCount > 0 ? "Apps to Block (\(selectedCount))" : "Choose Apps to Block",
                systemImage: "apps.iphone"
            )
        }
        .buttonStyle(.kawaiiOutlined)
        .disabled(!authManager.isAuthorized || isBlocking)
    }

    private var whitelistSection: some View {
        VStack(spacing: 8) {
            Button {
                showWhitelistPicker = true
            } label: {
                Label(
                    whitelistedCount > 0
                        ? "Strict Mode Whitelist (\(whitelistedCount))"
                        : "Choose Strict Mode Whitelist",
                    systemImage: "checkmark.shield"
                )
            }
            .buttonStyle(.kawaiiOutlined)
            .disabled(!authManager.isAuthorized || isBlocking)

            Text("Apps that stay available when strict mode blocks everything else. Only individual apps count — categories are ignored.")
                .font(.theme.caption(11))
                .foregroundStyle(Color.theme.text.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    private var startBlockButton: some View {
        Button {
            startBlock()
        } label: {
            Label("Start a \(selectedDurationMin.durationPhrase) Focus Block", systemImage: "timer")
        }
        .buttonStyle(.kawaiiPrimary(isDisabled: !canStartBlock))
        .disabled(!canStartBlock)
    }

    private var stopButton: some View {
        Button {
            stopBlock()
        } label: {
            Label("Stop / Unblock Now", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.kawaiiDestructive(isDisabled: !isBlocking))
        .disabled(!isBlocking)
    }

    // MARK: - Blocking

    private func startBlock() {
        let durationSeconds = selectedDurationMin * 60

        // Persist the strict-mode flag to the shared App Group so StudyHallMonitor applies
        // the correct shield policy when intervalDidStart fires (it fires almost immediately
        // since the schedule's interval start is "now"). Without this, the extension falls
        // back to treating the session as non-strict and re-shields using only the personal
        // blocklist, silently downgrading strict mode to blocklist-only enforcement.
        SessionContextStore.shared.setStrictMode(strictMode)
        // GRO-30: mark a personal session active so Shield/Monitor extensions have a local
        // counter to log "opened blocked app" attempts against — solo sessions never write a
        // group ActiveSessionContext, so without this the attempt would be silently dropped.
        SessionContextStore.shared.startPersonalSession()
        sessionStartAt = Date()
        sessionPlannedDurationMin = selectedDurationMin
        sessionWasStrict = strictMode

        if strictMode {
            BlockingManager.shared.blockStrict(whitelist: whitelistSelection)
        } else {
            BlocklistStore.shared.selection = selection
            BlockingManager.shared.block(selection: selection)
        }
        isBlocking = true
        timeRemaining = durationSeconds
        beginCountdown()

        rescheduleMonitoring(remainingSeconds: durationSeconds)
    }

    private func beginCountdown() {
        blockTask?.cancel()
        blockTask = Task {
            while !Task.isCancelled {
                let remaining = await MainActor.run { timeRemaining }
                guard remaining > 0 else { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    if timeRemaining > 0 {
                        timeRemaining -= 1
                    }
                }
            }
            await MainActor.run {
                guard isBlocking, timeRemaining <= 0 else { return }
                finishBlock(endedEarly: false)
            }
        }
    }

    private func addTime(minutes: Int) {
        guard isBlocking, minutes > 0 else { return }
        timeRemaining += minutes * 60
        sessionPlannedDurationMin += minutes
        rescheduleMonitoring(remainingSeconds: timeRemaining)
    }

    private func rescheduleMonitoring(remainingSeconds: Int) {
        let endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        let monitorSelection = strictMode ? effectiveMonitorSelection() : selection
        try? SessionActivityScheduler.startMonitoring(until: endDate, selection: monitorSelection)
    }

    private func stopBlock() {
        finishBlock(endedEarly: true)
    }

    private func finishBlock(endedEarly: Bool) {
        let wasBlocking = isBlocking
        blockTask?.cancel()
        blockTask = nil
        SessionActivityScheduler.stopMonitoring()
        BlockingManager.shared.clear()
        SessionContextStore.shared.setStrictMode(false)
        isBlocking = false
        timeRemaining = 0
        if wasBlocking {
            presentPersonalSummary(endedEarly: endedEarly)
        }
    }

    /// Drains the local "opened blocked app" counter and shows the personal session summary.
    /// Called from both the natural-completion path and a manual stop.
    private func presentPersonalSummary(endedEarly: Bool) {
        let openedCount = SessionContextStore.shared.endPersonalSession()
        guard let startAt = sessionStartAt else { return }

        personalSummary = PersonalSessionSummary(
            id: UUID().uuidString,
            plannedDurationMin: sessionPlannedDurationMin,
            startAt: startAt,
            endedAt: Date(),
            wasStrictMode: sessionWasStrict,
            endedEarly: endedEarly,
            openedBlockedAppCount: openedCount
        )
        sessionStartAt = nil
    }

    /// Personal blocklist with whitelist tokens subtracted — mirrors the same logic used for
    /// group sessions so a whitelisted app that also happens to be on the blocklist never
    /// triggers the backup "opened" event.
    private func effectiveMonitorSelection() -> FamilyActivitySelection {
        var effective = selection
        effective.applicationTokens.subtract(whitelistSelection.applicationTokens)
        effective.categoryTokens.subtract(whitelistSelection.categoryTokens)
        return effective
    }

    private func formattedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    ContentView()
}
