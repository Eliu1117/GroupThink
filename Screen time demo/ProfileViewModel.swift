//
//  ProfileViewModel.swift
//  Screen time demo
//

import Combine
import FirebaseFirestore

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    func startListening(userID: String?) {
        listener?.remove()
        listener = nil
        profile = nil
        errorMessage = nil

        guard let userID else {
            isLoading = false
            return
        }

        isLoading = true
        print("[Profile] Starting Firestore listener for \(userID)")

        let docRef = Firestore.firestore().collection("users").document(userID)
        listener = docRef.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    print("[Profile] Firestore listener error: \(error.localizedDescription)")
                    return
                }

                guard let snapshot else {
                    self.isLoading = false
                    self.errorMessage = "Profile data unavailable."
                    return
                }

                self.profile = UserProfile(document: snapshot)
                self.isLoading = false
                self.errorMessage = nil

                if let profile = self.profile {
                    print("[Profile] Loaded — \(profile.displayName), \(profile.focusMinutes) min, streak \(profile.currentStreak)")
                }
            }
        }
    }
}
