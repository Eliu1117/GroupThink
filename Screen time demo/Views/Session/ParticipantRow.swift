//
//  ParticipantRow.swift
//  Screen time demo
//
//  One participant's live presence state during a session.
//

import SwiftUI

struct ParticipantRow: View {
    let info: ParticipantInfo
    let isHost: Bool
    let isYou: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(info.displayName)
                    if isHost {
                        Text("Host")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                    if isYou {
                        Text("You").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            Spacer()
        }
    }

    private var icon: String {
        switch info.state {
        case .focused: return "checkmark.circle.fill"
        case .left: return "figure.walk.departure"
        case .opened: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch info.state {
        case .focused: return .green
        case .left: return .yellow
        case .opened: return .red
        }
    }

    private var label: String {
        switch info.state {
        case .focused: return "Focused"
        case .left: return "Left early"
        case .opened: return "Opened a blocked app"
        }
    }
}
