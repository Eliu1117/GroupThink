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
    private static let durationPresets = [10, 15, 20, 25, 30, 45, 60, 90]

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
    @State private var selectedDurationMin = 25
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
        return strictMode ? true : selectedCount > 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                statusSection

                VStack(spacing: 12) {
                    if !authManager.isAuthorized {
                        permissionButton
                    }

                    // GRO-36: duration segmented picker
                    durationPicker

                    // GRO-36: strict mode toggle
                    strictModeSection

                    chooseAppsButton
                    whitelistSection
                    startBlockButton
                    stopButton
                }

                Spacer(minLength: 0)
            }
            .padding()
            .kawaiiBackground()
            .navigationTitle("Home")
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

    // MARK: - Status

    private var statusSection: some View {
        VStack(spacing: 16) {
            HStack {
                Label(
                    authManager.isAuthorized ? "Authorized" : "Not Authorized",
                    systemImage: authManager.isAuthorized ? "checkmark.shield.fill" : "xmark.shield"
                )
                .font(.theme.body())
                .foregroundStyle(authManager.isAuthorized ? Color.theme.text : Color.theme.text.opacity(0.5))
                Spacer()
            }

            HStack {
                Text("Selected to block")
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text.opacity(0.6))
                Spacer()
                Text("\(selectedCount)")
                    .font(.theme.headline())
                    .foregroundStyle(Color.theme.text)
            }

            if isBlocking {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Focus Active")
                            .font(.theme.headline())
                            .foregroundStyle(Color.theme.text)
                        if strictMode {
                            Label("Strict", systemImage: "lock.shield.fill")
                                .font(.theme.caption())
                                .foregroundStyle(Color.theme.text)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.theme.secondary, in: Capsule())
                        }
                    }
                    Text(formattedTime(timeRemaining))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.theme.text)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.theme.primary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .kawaiiCard()
    }

    // MARK: - Duration picker (GRO-36)

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Duration")
                .font(.theme.caption())
                .foregroundStyle(Color.theme.text.opacity(0.6))
            Picker("Duration", selection: $selectedDurationMin) {
                ForEach(Self.durationPresets, id: \.self) { mins in
                    Text("\(mins)m").tag(mins)
                }
            }
            .pickerStyle(.segmented)
            .tint(Color.theme.primary)
            .disabled(isBlocking)
        }
        .padding(12)
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
            .tint(Color.theme.primary)
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

    private var permissionButton: some View {
        Button {
            Task { await authManager.requestAuthorization() }
        } label: {
            Label("Request Screen Time Permission", systemImage: "hand.raised.fill")
        }
        .buttonStyle(.kawaiiPrimary())
    }

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
            Label("Start \(selectedDurationMin)-Min Focus Block", systemImage: "timer")
        }
        .buttonStyle(.kawaiiPrimary(isDisabled: !canStartBlock))
        .disabled(!canStartBlock)
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            stopBlock()
        } label: {
            Label("Stop / Unblock Now", systemImage: "stop.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
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

        let endDate = Date().addingTimeInterval(TimeInterval(durationSeconds))
        // The "openedBlockedApp" backup event must track apps that are actually shielded.
        // In strict mode that's the personal blocklist minus the whitelist (never the
        // whitelist itself — the whitelist is what's ALLOWED, not blocked).
        let monitorSelection = strictMode ? effectiveMonitorSelection() : selection
        try? SessionActivityScheduler.startMonitoring(until: endDate, selection: monitorSelection)

        blockTask?.cancel()
        blockTask = Task {
            var remaining = durationSeconds
            while remaining > 0 {
                if Task.isCancelled { return }
                await MainActor.run { timeRemaining = remaining }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
            }
            await MainActor.run {
                BlockingManager.shared.clear()
                SessionActivityScheduler.stopMonitoring()
                SessionContextStore.shared.setStrictMode(false)
                isBlocking = false
                timeRemaining = 0
                blockTask = nil
                presentPersonalSummary(endedEarly: false)
            }
        }
    }

    private func stopBlock() {
        let wasBlocking = isBlocking
        blockTask?.cancel()
        blockTask = nil
        SessionActivityScheduler.stopMonitoring()
        BlockingManager.shared.clear()
        SessionContextStore.shared.setStrictMode(false)
        isBlocking = false
        timeRemaining = 0
        if wasBlocking {
            presentPersonalSummary(endedEarly: true)
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
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    ContentView()
}
