//
//  MorningRoutineSettingsView.swift  (GRO-32: struct renamed to RoutineSettingsView; file name kept for Xcode compat)
//  Screen time demo
//
//  UI for configuring a user's routine: lock window, unlock mode,
//  and the list of routine apps whose usage counts toward an activity-based unlock.
//  Also hosts the group-level "Enable Routines" toggle for group creators (GRO-32).
//

import FamilyControls
import SwiftUI

struct RoutineSettingsView: View {
    let groupID: String
    let currentUID: String
    /// Only group creators may toggle the group-level feature flag.
    let isGroupCreator: Bool
    /// Current value of `group.routineEnabled` passed in from the parent.
    let groupFeatureEnabled: Bool

    @State private var routine: Routine = .default
    @State private var routineApps: FamilyActivitySelection = .init()
    @State private var showAppPicker = false
    @State private var isSaving = false
    @State private var saveError: String?
    /// Mirrors the group-level enabled flag; toggled by the creator.
    @State private var featureEnabled: Bool

    @Environment(\.dismiss) private var dismiss

    init(
        groupID: String,
        currentUID: String,
        isGroupCreator: Bool,
        groupFeatureEnabled: Bool
    ) {
        self.groupID = groupID
        self.currentUID = currentUID
        self.isGroupCreator = isGroupCreator
        self.groupFeatureEnabled = groupFeatureEnabled
        self._featureEnabled = State(initialValue: groupFeatureEnabled)
    }

    // GRO-31: No NavigationStack here. The presenting sheet wraps this in its own stack.
    var body: some View {
        Form {
            // ── Group-level feature toggle (creator-only) ────────────────
            groupFeatureSection

            // ── Per-user schedule (all members) ─────────────────────────
            if featureEnabled {
                enableSection
                if routine.enabled {
                    lockWindowSection
                    unlockModeSection
                    routineAppsSection
                }
            }
        }
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || !featureEnabled)
            }
        }
        .familyActivityPicker(isPresented: $showAppPicker, selection: $routineApps)
        .overlay {
            if isSaving {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Error", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task {
            await loadRoutine()
            routineApps = RoutineService.shared.loadRoutineApps()
        }
    }

    // MARK: - Group feature toggle

    private var groupFeatureSection: some View {
        Section {
            if isGroupCreator {
                Toggle("Enable Routines for Group", isOn: $featureEnabled)
                    .onChange(of: featureEnabled) { _, newValue in
                        Task { await updateGroupFeature(enabled: newValue) }
                    }
            } else {
                HStack {
                    Label("Routines", systemImage: "sun.and.horizon.fill")
                    Spacer()
                    Image(systemName: featureEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(featureEnabled ? .green : .secondary)
                }
            }
        } header: {
            Text("Group Setting")
        } footer: {
            if isGroupCreator {
                Text("When enabled, all members configure their own routine schedules. You can toggle this anytime without affecting personal schedules.")
            } else {
                Text("Your group creator controls whether routines are active.")
            }
        }
    }

    // MARK: - Personal enable toggle

    private var enableSection: some View {
        Section {
            Toggle("Enable My Routine", isOn: $routine.enabled)
        } footer: {
            Text("When enabled, apps are blocked during your routine window until the unlock condition is met.")
        }
    }

    // MARK: - Lock window

    private var lockWindowSection: some View {
        Section("Lock Window") {
            HStack {
                Text("Lock at")
                Spacer()
                RoutineTimePicker(hour: $routine.lockHour, minute: $routine.lockMinute)
            }
            HStack {
                Text("Unlock by")
                Spacer()
                RoutineTimePicker(hour: $routine.unlockHour, minute: $routine.unlockMinute)
            }
        }
    }

    // MARK: - Unlock mode

    private var unlockModeSection: some View {
        Section {
            Picker("Mode", selection: $routine.unlockMode) {
                ForEach(RoutineUnlockMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if routine.unlockMode == .activityBased {
                Stepper(
                    "Require \(routine.unlockActivityMinutes) min of routine",
                    value: $routine.unlockActivityMinutes,
                    in: 1...60
                )
            }
        } header: {
            Text("Unlock Mode")
        } footer: {
            switch routine.unlockMode {
            case .timeBased:
                Text("Apps unlock automatically at the configured unlock time.")
            case .activityBased:
                Text("Apps unlock once you spend the required minutes inside your chosen routine apps (e.g. meditation, journaling).")
            }
        }
    }

    // MARK: - Routine apps

    private var routineAppsSection: some View {
        Section {
            if AuthorizationCenter.shared.authorizationStatus == .approved {
                Button {
                    showAppPicker = true
                } label: {
                    HStack {
                        Label("Choose Routine Apps", systemImage: "app.badge.checkmark")
                        Spacer()
                        if !routineApps.applicationTokens.isEmpty {
                            Text("\(routineApps.applicationTokens.count) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Label("Screen Time permission required", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Routine Apps")
        } footer: {
            if routine.unlockMode == .activityBased {
                Text("These apps stay accessible during the routine window and their usage accumulates toward your unlock threshold.")
            } else {
                Text("These apps stay accessible during the routine window even before the unlock time.")
            }
        }
    }

    // MARK: - Actions

    private func loadRoutine() async {
        do {
            routine = try await RoutineService.shared.loadRoutine(uid: currentUID)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        saveError = nil

        do {
            try await RoutineService.shared.saveRoutine(uid: currentUID, routine: routine)
            RoutineService.shared.persistRoutineApps(routineApps)
            try RoutineScheduler.startMonitoring(routine: routine, routineApps: routineApps)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func updateGroupFeature(enabled: Bool) async {
        do {
            // Writes to Firestore key "morningRoutineEnabled" for backward compat (GRO-32).
            try await GroupService.shared.updateGroupSetting(
                groupID: groupID,
                requesterUID: currentUID,
                key: "morningRoutineEnabled",
                value: enabled
            )
        } catch {
            saveError = error.localizedDescription
            // Revert the toggle on failure.
            featureEnabled = !enabled
        }
    }
}

// MARK: - Supporting view

private struct RoutineTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    private var binding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = hour
                comps.minute = minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour = comps.hour ?? hour
                minute = comps.minute ?? minute
            }
        )
    }

    var body: some View {
        DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
            .labelsHidden()
    }
}
