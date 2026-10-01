//
//  MemberAvatarView.swift
//  Screen time demo
//
//  Small circular avatar used anywhere a group member needs to be identified at a glance
//  (Focus Roster, group Members list, …) — mirrors `ProfileView`'s own avatar resolution so
//  every screen agrees on the same precedence: a real uploaded photo wins over a chosen
//  built-in drink-character avatar, which wins over an initials placeholder for members who
//  haven't finished Profile Setup yet.
//

import SwiftUI

struct MemberAvatarView: View {
    let name: String
    let avatarAssetName: String?
    let photoURL: URL?
    var size: CGFloat = 36

    // See `KawaiiCardModifier` — guarantees this redraws with fresh `Color.theme.*` values.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.theme.surface, lineWidth: max(1.5, size * 0.05)))
    }

    @ViewBuilder
    private var content: some View {
        if let photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if let avatarAssetName, let option = AvatarOption(rawValue: avatarAssetName) {
            Image(option.assetName)
                .resizable()
                .scaledToFit()
                .padding(size * 0.16)
                .background(Color.theme.secondary.opacity(0.18))
        } else {
            Color.theme.primary.opacity(0.4)
                .overlay {
                    Text(initials)
                        .font(.theme.heading(size * 0.4))
                        .foregroundStyle(Color.theme.text)
                }
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

#Preview {
    HStack(spacing: 12) {
        MemberAvatarView(name: "Alex", avatarAssetName: "boba", photoURL: nil)
        MemberAvatarView(name: "Jordan Lee", avatarAssetName: nil, photoURL: nil)
    }
    .padding()
}
