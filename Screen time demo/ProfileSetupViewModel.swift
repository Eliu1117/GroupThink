//
//  ProfileSetupViewModel.swift
//  Screen time demo
//
//  State + save logic for the username/avatar Profile Setup screen.
//

import Combine
import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class ProfileSetupViewModel: ObservableObject {
    @Published var username: String = ""
    /// Pre-seeded with a random pick so "Skip for now" (or simply never tapping a tile)
    /// still lands on one of the 5 defaults, per the "randomly assign a default" requirement.
    @Published var selectedAvatar: AvatarOption = .random()
    @Published var customAvatarItem: PhotosPickerItem?
    @Published private(set) var customAvatarImage: Image?
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    /// True once the user has picked one of the 5 built-in avatars — used only to decide
    /// whether a just-uploaded custom photo should visually "win" over a stale grid
    /// selection; it does not affect which value ultimately gets saved.
    private var pickedBuiltInAvatar = false

    /// Prefills from an existing profile — used when re-opening this screen as "Edit Profile".
    func prefill(from profile: UserProfile?) {
        guard let profile else { return }
        if profile.profileSetupCompleted {
            username = profile.username
        }
        if let assetName = profile.avatarAssetName, let option = AvatarOption(rawValue: assetName) {
            selectedAvatar = option
            pickedBuiltInAvatar = true
        }
    }

    func selectAvatar(_ avatar: AvatarOption) {
        selectedAvatar = avatar
        pickedBuiltInAvatar = true
        customAvatarImage = nil
        customAvatarItem = nil
    }

    var isCustomAvatarSelected: Bool { customAvatarImage != nil }

    /// Loads the PhotosPicker selection into a preview image.
    ///
    /// NOTE (mock only, per spec): there is no Firebase Storage integration yet, so this
    /// preview is never uploaded or persisted — it only affects the local selection state
    /// for this screen session. `save()` still writes one of the 5 built-in avatar names to
    /// Firestore even if a custom photo was "selected" here.
    func loadCustomAvatarPreview() async {
        guard let customAvatarItem else { return }
        do {
            guard
                let data = try await customAvatarItem.loadTransferable(type: Data.self),
                let uiImage = UIImage(data: data)
            else {
                errorMessage = "Couldn't load that photo — try a different one."
                return
            }
            customAvatarImage = Image(uiImage: uiImage)
            pickedBuiltInAvatar = false
            print("[ProfileSetup] Loaded custom avatar preview (mock only — no storage upload wired up yet)")
        } catch {
            errorMessage = "Couldn't load that photo — try a different one."
        }
    }

    @discardableResult
    func save(uid: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            // `selectedAvatar` already defaults to a random pick (see the property above),
            // so this covers both an explicit choice and a bypassed one uniformly.
            try await UserService.shared.updateProfile(
                uid: uid,
                username: username,
                avatarAssetName: selectedAvatar.assetName
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("[ProfileSetup] Save failed: \(error.localizedDescription)")
            return false
        }
    }
}
