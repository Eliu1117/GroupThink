//
//  JoinGroupView.swift
//  Screen time demo
//

import SwiftUI

struct JoinGroupView: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced())
                } footer: {
                    Text("Ask a group member for their 6-character invite code.")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.clearError()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task {
                            if await viewModel.joinGroup(inviteCode: inviteCode) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 4
                        || viewModel.isSubmitting
                    )
                }
            }
            .overlay {
                if viewModel.isSubmitting {
                    ProgressView("Joining…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

#Preview {
    JoinGroupView(viewModel: GroupsViewModel())
}
