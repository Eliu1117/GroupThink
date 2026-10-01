//
//  ProfileSetupView.swift
//  Screen time demo
//
//  Username + avatar setup screen. Used both as a one-time onboarding gate (shown once
//  after Screen Time permission, before MainTabView, when the user hasn't finished setup)
//  and as an "Edit Profile" sheet reachable later from ProfileView.
//

import FirebaseAuth
import PhotosUI
import SwiftUI

struct ProfileSetupView: View {
    /// When true, this is the first-run onboarding gate: no "Cancel" affordance, and
    /// finishing calls `onComplete` instead of dismissing (there's nothing to dismiss to —
    /// RootView swaps this screen out for MainTabView once `onComplete` fires).
    let isOnboarding: Bool
    var onComplete: (() -> Void)?

    @EnvironmentObject private var authViewModel: AuthViewModel
    /// Subscribing here forces this screen's `body` to re-run on theme change — see the
    /// comment on `ContentView`'s equivalent property for why this is needed.
    @EnvironmentObject private var themeSettings: ThemeSettings
    @StateObject private var viewModel = ProfileSetupViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var usernameFieldFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 100), spacing: 16)]

    init(isOnboarding: Bool, onComplete: (() -> Void)? = nil) {
        self.isOnboarding = isOnboarding
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    usernameField
                    avatarSection
                    errorSection
                    actions
                }
                .padding(24)
            }
            .kawaiiBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .task {
            guard let uid = authViewModel.user?.uid else { return }
            let profiles = await UserService.shared.fetchProfiles(for: [uid])
            viewModel.prefill(from: profiles[uid])
        }
        .onChange(of: viewModel.customAvatarItem) { _, _ in
            Task { await viewModel.loadCustomAvatarPreview() }
        }
        // Explicitly *reading* `themeSettings.theme` (not just declaring the property
        // unused) guarantees this screen's buttons/cards actually repaint on theme change.
        .animation(.easeInOut(duration: 0.2), value: themeSettings.theme)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.theme.primary.opacity(0.45))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.theme.text)
            }

            Text(isOnboarding ? "Set Up Your Profile" : "Edit Profile")
                .font(.theme.heading(28))
                .foregroundStyle(Color.theme.text)

            Text("Pick a username and a little avatar so your study group knows it's you.")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Username

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            TextField("Choose a username", text: $viewModel.username)
                .focused($usernameFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.theme.body())
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.theme.text.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Avatar grid

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Avatar")
                .font(.theme.headline())
                .foregroundStyle(Color.theme.text)

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(AvatarOption.primaryGridOptions) { option in
                    avatarCell(option)
                }
                uploadCustomCell
            }

            // Only surfaced once a family with multiple skins (Boba, Energy Drink, Milk,
            // Water, …) is the active selection — keeps the grid uncluttered and lets each
            // family grow its own set of skins independently without stacking multiple
            // picker rows at once.
            if !viewModel.isCustomAvatarSelected && viewModel.selectedAvatar.hasSkinVariants {
                skinPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: viewModel.selectedAvatar.family)
    }

    /// Each multi-skin family (Boba, Energy Drink, Milk, Water, …) is represented by a
    /// single grid cell above (always showing as whichever skin is currently active for
    /// that family, defaulting to Classic). This lets the user swap that cell's underlying
    /// artwork/color scheme without the grid growing a separate entry per skin — mirrors
    /// `SettingsView`'s theme-grid treatment.
    private var skinPicker: some View {
        let family = viewModel.selectedAvatar.family

        return VStack(alignment: .leading, spacing: 10) {
            Text("\(family.displayName) Color")
                .font(.theme.caption().weight(.semibold))
                .foregroundStyle(Color.theme.text.opacity(0.7))

            HStack(spacing: 14) {
                ForEach(family.mainOption.familySkins) { skin in
                    skinSwatch(skin)
                }
            }
        }
        .padding(.top, 4)
    }

    private func skinSwatch(_ skin: AvatarOption) -> some View {
        let isSelected = !viewModel.isCustomAvatarSelected && viewModel.selectedAvatar == skin

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.selectAvatar(skin)
            }
        } label: {
            VStack(spacing: 4) {
                Image(skin.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(width: 44, height: 44)
                    .background(Color.theme.secondary.opacity(0.18))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            isSelected ? Color.theme.primary : Color.theme.text.opacity(0.15),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                    )

                Text(skin.skinLabel)
                    .font(.theme.caption(10))
                    .foregroundStyle(Color.theme.text.opacity(isSelected ? 0.9 : 0.5))
            }
        }
        .buttonStyle(.plain)
    }

    /// The currently-active skin for a given family — whichever skin is selected if it
    /// belongs to that family, falling back to that family's default ("Classic") skin
    /// otherwise. Used so a family's main grid cell reflects whichever skin was last chosen.
    private func activeSkin(for family: AvatarOption.Family) -> AvatarOption {
        viewModel.selectedAvatar.family == family ? viewModel.selectedAvatar : family.mainOption
    }

    private func avatarCell(_ option: AvatarOption) -> some View {
        // Every grid cell always represents whichever skin is currently active for its
        // family, so its art/label/selection state track `activeSkin(for:)` rather than the
        // static main-skin case passed in from `primaryGridOptions`.
        let family = option.family
        let displayOption = activeSkin(for: family)
        let isSelected = !viewModel.isCustomAvatarSelected && viewModel.selectedAvatar.family == family

        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.selectAvatar(displayOption)
            }
        } label: {
            VStack(spacing: 6) {
                avatarCircle(isSelected: isSelected) {
                    Image(displayOption.assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                }

                Text(family.displayName)
                    .font(.theme.caption(11))
                    .foregroundStyle(Color.theme.text.opacity(isSelected ? 0.9 : 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var uploadCustomCell: some View {
        // Snapshot into plain local values BEFORE entering PhotosPicker's `label` closure:
        // that closure isn't inferred as MainActor-isolated, so reading `viewModel`'s
        // (MainActor) properties directly from inside it triggers isolation warnings.
        let isSelected = viewModel.isCustomAvatarSelected
        let previewImage = viewModel.customAvatarImage

        return PhotosPicker(selection: $viewModel.customAvatarItem, matching: .images) {
            VStack(spacing: 6) {
                avatarCircle(isSelected: isSelected) {
                    if let previewImage {
                        previewImage
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                    }
                }

                Text("Upload Custom Avatar")
                    .font(.theme.caption(11))
                    .foregroundStyle(Color.theme.text.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    /// Circular avatar frame: transparent-background PNGs get a soft tinted backing so
    /// the character pops, plus a subtle shadow and a colored ring + checkmark when selected.
    @ViewBuilder
    private func avatarCircle<Content: View>(isSelected: Bool, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .bottomTrailing) {
            content()
                .frame(width: 72, height: 72)
                .background(Color.theme.secondary.opacity(0.18))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(isSelected ? Color.theme.primary : Color.theme.text.opacity(0.15), lineWidth: isSelected ? 3 : 1.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                .scaleEffect(isSelected ? 1.06 : 1.0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.theme.primary)
                    .background(Color.theme.surface, in: Circle())
                    .offset(x: 3, y: 3)
            }
        }
    }

    // MARK: - Error + actions

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.theme.caption())
                .foregroundStyle(.red)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                usernameFieldFocused = false
                Task { await save() }
            } label: {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(Color.theme.text)
                        .frame(maxWidth: .infinity)
                } else {
                    Label(isOnboarding ? "Continue" : "Save Changes", systemImage: "checkmark.circle.fill")
                }
            }
            .buttonStyle(.kawaiiPrimary(isDisabled: viewModel.isSaving))
            .disabled(viewModel.isSaving)

            if isOnboarding {
                Button {
                    usernameFieldFocused = false
                    Task { await save() }
                } label: {
                    Text("Skip for now")
                        .font(.theme.caption())
                        .foregroundStyle(Color.theme.text.opacity(0.55))
                }
                .disabled(viewModel.isSaving)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func save() async {
        guard let uid = authViewModel.user?.uid else { return }
        let success = await viewModel.save(uid: uid)
        guard success else { return }

        if isOnboarding {
            onComplete?()
        } else {
            dismiss()
        }
    }
}

#Preview {
    ProfileSetupView(isOnboarding: true)
        .environmentObject(AuthViewModel())
        .environmentObject(ThemeSettings.shared)
}
