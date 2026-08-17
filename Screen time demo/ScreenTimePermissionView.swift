//
//  ScreenTimePermissionView.swift
//  Screen time demo
//
//  Shown after sign-in until the user grants Screen Time / FamilyControls
//  authorization. Blocking and shielding cannot run without this.
//

import SwiftUI
import UIKit

struct ScreenTimePermissionView: View {
    @ObservedObject private var authManager = AuthorizationManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    stepsCard
                    buttons
                }
                .padding(24)
            }
            .kawaiiBackground()
            .navigationBarTitleDisplayMode(.inline)
            .task {
                authManager.refreshAuthorizationStatus()
            }
            .onAppear {
                authManager.refreshAuthorizationStatus()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.theme.primary.opacity(0.45))
                    .frame(width: 72, height: 72)
                Image(systemName: "hourglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.theme.text)
            }

            Text("Enable Screen Time")
                .font(.theme.heading(28))
                .foregroundStyle(Color.theme.text)

            Text("GroupThink uses Apple’s Screen Time APIs to block distracting apps during a Focus Block. We need your permission before you can start.")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to turn it on")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            permissionStep(
                number: 1,
                title: "Tap Enable Screen Time",
                detail: "We’ll open Apple’s permission sheet for this app."
            )
            permissionStep(
                number: 2,
                title: "Allow on this device",
                detail: "Choose Continue, then confirm with Face ID, Touch ID, or your passcode."
            )
            permissionStep(
                number: 3,
                title: "If you don’t see the prompt",
                detail: "Open Settings → Screen Time and make sure this app is allowed. You can also tap Open Settings below."
            )
        }
        .kawaiiCard()
    }

    private func permissionStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)
                .frame(width: 28, height: 28)
                .background(Color.theme.primary, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text)
                Text(detail)
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.55))
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await authManager.requestAuthorization() }
            } label: {
                Label("Enable Screen Time", systemImage: "checkmark.shield.fill")
            }
            .buttonStyle(.kawaiiPrimary())

            Button {
                openSystemSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.kawaiiOutlined)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ScreenTimePermissionView()
}
