//
//  BlockingDemoView.swift
//  Screen time demo
//
//  Phase 0 standalone blocking test: request permission, pick apps, run a local
//  10-minute block. Kept reachable from Profile for on-device verification.
//

import FamilyControls
import SwiftUI

struct BlockingDemoView: View {
    private static let blockDurationSeconds = 600

    @StateObject private var authManager = AuthorizationManager.shared
    @StateObject private var blocklist = BlocklistStore.shared

    @State private var showPicker = false
    @State private var isBlocking = false
    @State private var timeRemaining = 0
    @State private var blockTask: Task<Void, Never>?

    private var canStartBlock: Bool {
        authManager.isAuthorized && blocklist.hasSelection && !isBlocking
    }

    var body: some View {
        VStack(spacing: 24) {
            statusSection
            VStack(spacing: 12) {
                permissionButton
                chooseAppsButton
                startBlockButton
                stopButton
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Blocking Test")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showPicker, selection: $blocklist.selection)
        .onAppear { authManager.refreshAuthorizationStatus() }
    }

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
                Text("Selected to block").foregroundStyle(.secondary)
                Spacer()
                Text("\(blocklist.selectedCount)").fontWeight(.semibold)
            }
            if isBlocking {
                VStack(spacing: 8) {
                    Text("Blocking active").font(.headline).foregroundStyle(.orange)
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

    private var permissionButton: some View {
        Button {
            Task { await authManager.requestAuthorization() }
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
            Label("Choose Apps to Block", systemImage: "apps.iphone").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!authManager.isAuthorized || isBlocking)
    }

    private var startBlockButton: some View {
        Button {
            startBlock()
        } label: {
            Label("Start 10-Minute Block", systemImage: "timer").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!canStartBlock)
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            stopBlock()
        } label: {
            Label("Stop / Unblock Now", systemImage: "stop.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!isBlocking)
    }

    private func startBlock() {
        BlockingManager.shared.block(selection: blocklist.selection)
        isBlocking = true
        timeRemaining = Self.blockDurationSeconds

        blockTask?.cancel()
        blockTask = Task {
            var remaining = Self.blockDurationSeconds
            while remaining > 0 {
                if Task.isCancelled { return }
                timeRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
            }
            BlockingManager.shared.clear()
            isBlocking = false
            timeRemaining = 0
            blockTask = nil
        }
    }

    private func stopBlock() {
        blockTask?.cancel()
        blockTask = nil
        BlockingManager.shared.clear()
        isBlocking = false
        timeRemaining = 0
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    NavigationStack { BlockingDemoView() }
}
