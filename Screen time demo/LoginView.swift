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
                ZStack {
                    Circle()
                        .fill(Color.theme.primary.opacity(0.4))
                        .frame(width: 96, height: 96)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.theme.text)
                }

                Text("Study Hall")
                    .font(.theme.heading(32))
                    .foregroundStyle(Color.theme.text)

                Text("Study together. Stay accountable.")
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text.opacity(0.6))
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
                .clipShape(Capsule())
                .disabled(authViewModel.isLoading)

                if authViewModel.isLoading {
                    ProgressView("Signing in…")
                        .tint(Color.theme.text)
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
        .kawaiiBackground()
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
