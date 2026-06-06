//
//  LoginView.swift
//  Screen time demo
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("Study Hall")
                    .font(.largeTitle.bold())

                Text("Study together. Stay accountable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    authViewModel.prepareAppleSignInRequest(request)
                } onCompletion: { result in
                    authViewModel.handleAppleSignInCompletion(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .disabled(authViewModel.isLoading)

                if authViewModel.isLoading {
                    ProgressView("Signing in…")
                }

                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
