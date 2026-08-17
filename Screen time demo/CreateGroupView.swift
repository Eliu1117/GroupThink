//
//  CreateGroupView.swift
//  Screen time demo
//

import SwiftUI

struct CreateGroupView: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var sessionDurationMin = 30

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

                Section {
                    DurationWheelPicker(totalMinutes: $sessionDurationMin)
                } header: {
                    Label("Session Length", systemImage: "clock.fill")
                } footer: {
                    Text("Default length for this group’s study halls. You can change it before each session.")
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .kawaiiListBackground()
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
                            if await viewModel.createGroup(name: groupName, durationMin: sessionDurationMin) {
                                dismiss()
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isSubmitting
                        || sessionDurationMin == 0
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
