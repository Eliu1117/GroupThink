//
//  LoginView.swift
//  Screen time demo
//
//  Sign in with Apple entry point.
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var account: AccountManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Study Hall")
                    .font(.largeTitle.bold())
                Text("Lock in with your friends.\nStay focused together.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                account.prepareAppleRequest(request)
            } onCompletion: { result in
                account.handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Blocking is on-device and based on social accountability,\nnot hard enforcement.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .alert("Sign-in failed", isPresented: .constant(account.errorMessage != nil)) {
            Button("OK") { account.errorMessage = nil }
        } message: {
            Text(account.errorMessage ?? "")
        }
    }
}

#Preview {
    LoginView().environmentObject(AccountManager.shared)
}
