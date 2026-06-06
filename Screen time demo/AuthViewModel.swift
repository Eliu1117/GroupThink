//
//  AuthViewModel.swift
//  Screen time demo
//

import AuthenticationServices
import Combine
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var currentNonce: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        print("[Auth] AuthViewModel initialized")
        listenToAuthState()
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    // MARK: - Apple Sign-In (called from UI callbacks)

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        print("[Auth] Preparing Apple Sign-In request")
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        Task {
            await processAppleSignInCompletion(result)
        }
    }

    func signOut() {
        print("[Auth] Sign-out requested")
        do {
            try Auth.auth().signOut()
            errorMessage = nil
            print("[Auth] Sign-out succeeded")
        } catch {
            errorMessage = error.localizedDescription
            print("[Auth] Sign-out failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Auth state

    private func listenToAuthState() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.user = user
                self.isAuthenticated = user != nil
                if let user {
                    print("[Auth] Auth state changed — signed in as \(user.uid)")
                } else {
                    print("[Auth] Auth state changed — signed out")
                }
            }
        }
    }

    // MARK: - Apple → Firebase flow

    private func processAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            print("[Auth] Apple Sign-In failed: \(error.localizedDescription)")
            return

        case .success(let authorization):
            print("[Auth] Apple Sign-In authorization received")
            await signInToFirebase(with: authorization)
        }
    }

    private func signInToFirebase(with authorization: ASAuthorization) async {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            errorMessage = "Invalid Apple credential type."
            print("[Auth] Firebase sign-in aborted — credential is not ASAuthorizationAppleIDCredential")
            return
        }

        guard let nonce = currentNonce else {
            errorMessage = "Missing sign-in nonce. Please try again."
            print("[Auth] Firebase sign-in aborted — currentNonce is nil")
            return
        }

        guard
            let identityToken = appleCredential.identityToken,
            let idTokenString = String(data: identityToken, encoding: .utf8)
        else {
            errorMessage = "Unable to read Apple identity token."
            print("[Auth] Firebase sign-in aborted — identity token missing or unreadable")
            return
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )

        do {
            print("[Auth] Signing in to Firebase with Apple credential")
            let authResult = try await Auth.auth().signIn(with: credential)
            print("[Auth] Firebase sign-in succeeded — uid: \(authResult.user.uid)")
            try await createUserDocumentIfNeeded(
                for: authResult.user,
                fullName: appleCredential.fullName
            )
        } catch {
            errorMessage = error.localizedDescription
            print("[Auth] Firebase sign-in failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Firestore

    private func createUserDocumentIfNeeded(for user: User, fullName: PersonNameComponents?) async throws {
        let docRef = Firestore.firestore().collection("users").document(user.uid)
        let snapshot = try await docRef.getDocument()

        if snapshot.exists {
            print("[Auth] Firestore user doc already exists for \(user.uid) — skipping create")
            return
        }

        let displayName = resolvedDisplayName(firebaseUser: user, appleFullName: fullName)
        let userData: [String: Any] = [
            "displayName": displayName,
            "photoURL": user.photoURL?.absoluteString ?? NSNull(),
            "stats": [
                "focusMinutes": 0,
                "currentStreak": 0,
            ],
        ]

        try await docRef.setData(userData)
        print("[Auth] Firestore user doc created for \(user.uid) — displayName: \(displayName)")
    }

    private func resolvedDisplayName(firebaseUser: User, appleFullName: PersonNameComponents?) -> String {
        if let firebaseName = firebaseUser.displayName, !firebaseName.isEmpty {
            return firebaseName
        }

        if let appleFullName {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: appleFullName)
            if !formatted.isEmpty {
                return formatted
            }
        }

        return "User"
    }

    // MARK: - Nonce helpers (Firebase-recommended pattern)

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
