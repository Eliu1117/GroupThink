//
//  ApplyingThemeView.swift
//  Screen time demo
//
//  Brief full-screen transition shown while "Apply Theme" (see `SettingsView`) forces a
//  guaranteed, full rebuild of every tab's content — mirrors iOS's own "Setting
//  Wallpaper…" cover shown while it applies a new wallpaper system-wide.
//

import SwiftUI

struct ApplyingThemeView: View {
    let theme: AppTheme

    @State private var iconRotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.theme.primary.opacity(0.35))
                    .frame(width: 108, height: 108)

                Image(theme.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .frame(width: 92, height: 92)
            }
            .rotationEffect(.degrees(iconRotation))

            VStack(spacing: 6) {
                Text("Applying \(theme.displayName)…")
                    .font(.theme.headline())
                    .foregroundStyle(Color.theme.text)

                Text("Just a moment")
                    .font(.theme.caption())
                    .foregroundStyle(Color.theme.text.opacity(0.55))
            }

            ProgressView()
                .tint(Color.theme.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.theme.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                iconRotation = 8
            }
        }
    }
}

#Preview {
    ApplyingThemeView(theme: .matcha)
}
