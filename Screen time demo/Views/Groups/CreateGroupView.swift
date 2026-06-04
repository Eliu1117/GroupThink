//
//  CreateGroupView.swift
//  Screen time demo
//

import SwiftUI

struct CreateGroupView: View {
    @ObservedObject var viewModel: GroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Group name") {
                    TextField("e.g. Finals Crew", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            if await viewModel.createGroup(name: name) { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isWorking)
                }
            }
            .alert("Couldn't create group", isPresented: errorBinding) {
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
