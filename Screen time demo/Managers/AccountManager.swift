//
//  AccountManager.swift
//  Screen time demo
//
//  Handles Sign in with Apple -> Firebase Auth, and exposes the signed-in user
//  document to the rest of the app.
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation

@MainActor
final class AccountManager: ObservableObject {
    static let shared = AccountManager()

    enum AuthState {
        case loading
        case signedOut
        case signedIn(uid: String)
    }

    @Published private(set) var authState: AuthState = .loading
    @Published private(set) var currentUser: AppUser?
    @Published var errorMessage: String?

    private var authListener: AuthStateDidChangeListenerHandle?
    private var userListener: ListenerRegistration?
    private var currentNonce: String?

    var uid: String? {
        if case let .signedIn(uid) = authState { return uid }
        return nil
    }

    private init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if let user {
                    self.authState = .signedIn(uid: user.uid)
                    self.startObservingUser(uid: user.uid)
                } else {
                    self.authState = .signedOut
                    self.stopObservingUser()
                    self.currentUser = nil
                }
            }
        }
    }

    // MARK: - Sign in with Apple

    /// Configures the Apple authorization request with a fresh nonce.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Handles the result from `SignInWithAppleButton`.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            Task { await signIn(with: authorization) }
        case let .failure(error):
            // User-cancelled is not an error worth surfacing.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        }
    }

    private func signIn(with authorization: ASAuthorization) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            errorMessage = "Could not read Apple credentials."
            return
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: firebaseCredential)
            let displayName = Self.resolveDisplayName(
                from: credential.fullName,
                fallback: result.user.displayName ?? result.user.email ?? "Studier"
            )
            try await UserService.shared.upsertUser(
                uid: result.user.uid,
                displayName: displayName,
                photoURL: result.user.photoURL?.absoluteString
            )
            await NotificationManager.shared.syncTokenForCurrentUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            if let uid, let token = NotificationManager.shared.currentToken {
                Task { try? await UserService.shared.removeFCMToken(uid: uid, token: token) }
            }
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - User document

    private func startObservingUser(uid: String) {
        stopObservingUser()
        userListener = UserService.shared.observeUser(uid: uid) { [weak self] user in
            Task { @MainActor in self?.currentUser = user }
        }
    }

    private func stopObservingUser() {
        userListener?.remove()
        userListener = nil
    }

    private static func resolveDisplayName(from name: PersonNameComponents?, fallback: String) -> String {
        guard let name else { return fallback }
        let formatted = PersonNameComponentsFormatter().string(from: name)
        return formatted.isEmpty ? fallback : formatted
    }

    // MARK: - Nonce helpers (per Firebase Sign in with Apple guidance)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                precondition(status == errSecSuccess, "Unable to generate nonce.")
                return random
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
