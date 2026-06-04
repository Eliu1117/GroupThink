//
//  JoinGroupView.swift
//  Screen time demo
//

import SwiftUI

struct JoinGroupView: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                } footer: {
                    Text("Ask a group member for their 6-character invite code.")
                }
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task {
                            if await viewModel.joinGroup(inviteCode: code) { dismiss() }
                        }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).count < 4 || viewModel.isWorking)
                }
            }
            .alert("Couldn't join", isPresented: errorBinding) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }
}
