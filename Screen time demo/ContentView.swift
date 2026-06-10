//
//  ContentView.swift
//  Screen time demo
//

import FamilyControls
import SwiftUI

struct ContentView: View {
    private static let blockDurationSeconds = 600

    @StateObject private var authManager = AuthorizationManager.shared

    @State private var selection = BlocklistStore.shared.selection
    @State private var showPicker = false
    @State private var whitelistSelection = BlocklistStore.shared.whitelistSelection
    @State private var showWhitelistPicker = false
    @State private var isBlocking = false
    @State private var timeRemaining = 0
    @State private var blockTask: Task<Void, Never>?

    private var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count
    }

    private var whitelistedCount: Int {
        whitelistSelection.applicationTokens.count
    }

    private var canStartBlock: Bool {
        authManager.isAuthorized && selectedCount > 0 && !isBlocking
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                statusSection

                VStack(spacing: 12) {
                    permissionButton
                    chooseAppsButton
                    whitelistSection
                    startBlockButton
                    stopButton
                }

                Spacer(minLength: 0)
            }
            .padding()
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
                .foregroundStyle(authManager.isAuthorized ? .green : .secondary)
                Spacer()
            }

            HStack {
                Text("Selected to block")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedCount)")
                    .fontWeight(.semibold)
            }

            if isBlocking {
                VStack(spacing: 8) {
                    Text("Blocking active")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(formattedTime(timeRemaining))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Buttons

    private var permissionButton: some View {
        Button {
            Task {
                await authManager.requestAuthorization()
            }
        } label: {
            Label(
                authManager.isAuthorized ? "Screen Time Permission Granted" : "Request Screen Time Permission",
                systemImage: "hand.raised.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(authManager.isAuthorized)
    }

    private var chooseAppsButton: some View {
        Button {
            showPicker = true
        } label: {
            Label("Choose Apps to Block", systemImage: "apps.iphone")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            .disabled(!authManager.isAuthorized || isBlocking)

            Text("Apps that stay available when a strict group session blocks everything else. Only individual apps count — categories are ignored.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var startBlockButton: some View {
        Button {
            startBlock()
        } label: {
            Label("Start 10-Minute Block", systemImage: "timer")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
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
        .disabled(!isBlocking)
    }

    // MARK: - Blocking

    private func startBlock() {
        BlocklistStore.shared.selection = selection
        BlockingManager.shared.block(selection: selection)
        isBlocking = true
        timeRemaining = Self.blockDurationSeconds

        let endDate = Date().addingTimeInterval(TimeInterval(Self.blockDurationSeconds))
        try? SessionActivityScheduler.startMonitoring(until: endDate, selection: selection)

        blockTask?.cancel()
        blockTask = Task {
            var remaining = Self.blockDurationSeconds
            while remaining > 0 {
                if Task.isCancelled { return }
                await MainActor.run {
                    timeRemaining = remaining
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
            }
            await MainActor.run {
                BlockingManager.shared.clear()
                SessionActivityScheduler.stopMonitoring()
                isBlocking = false
                timeRemaining = 0
                blockTask = nil
            }
        }
    }

    private func stopBlock() {
        blockTask?.cancel()
        blockTask = nil
        SessionActivityScheduler.stopMonitoring()
        BlockingManager.shared.clear()
        isBlocking = false
        timeRemaining = 0
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
