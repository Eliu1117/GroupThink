//
//  CreateGroupView.swift
//  Screen time demo
//

import SwiftUI

struct CreateGroupView: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $groupName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Give your study hall a name your friends will recognize.")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.clearError()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel.createGroup(name: groupName) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isSubmitting
                    )
                }
            }
            .overlay {
                if viewModel.isSubmitting {
                    ProgressView("Creating…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

#Preview {
    CreateGroupView(viewModel: GroupsViewModel())
}
