//
//  DowntimeSettingsView.swift
//  Screen time demo
//
//  UI for configuring a user's personal downtime schedule and managing
//  peer override requests for the group.
//

import FamilyControls
import SwiftUI

struct DowntimeSettingsView: View {
    let groupID: String
    let currentUID: String
    /// Only group creators may toggle the group-level feature flag.
    let isGroupCreator: Bool
    /// Current value of `group.downtimeEnabled` passed in from the parent.
    let groupFeatureEnabled: Bool

    @State private var schedule: DowntimeSchedule = .default
    @State private var allowedApps: FamilyActivitySelection = .init()
    @State private var showAppPicker = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var overrideRequests: [DowntimeOverrideRequest] = []
    /// Opaque hold on the Firestore ListenerRegistration so it is retained across re-renders.
    @State private var overrideListener: (any AnyObject)?
    @State private var showOverrideSheet = false
    @State private var overrideExpiryTask: Task<Void, Never>?
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
            groupFeatureSection
            if featureEnabled {
                scheduleSection
                allowedAppsSection
                if !overrideRequests.isEmpty {
                    overrideSection
                }
                requestOverrideSection
            }
        }
        .kawaiiListBackground()
        .navigationTitle("Downtime")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await saveSchedule() } }
                    .disabled(isSaving)
            }
        }
        .familyActivityPicker(isPresented: $showAppPicker, selection: $allowedApps)
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
            await loadSchedule()
            allowedApps = DowntimeService.shared.loadAllowedApps()
            startOverrideListener()
        }
        .onDisappear {
            overrideExpiryTask?.cancel()
        }
    }

    // MARK: - Group feature toggle (GRO-32)

    private var groupFeatureSection: some View {
        Section {
            if isGroupCreator {
                Toggle("Enable Downtime for Group", isOn: $featureEnabled)
                    .onChange(of: featureEnabled) { _, newValue in
                        Task { await updateGroupFeature(enabled: newValue) }
                    }
            } else {
                HStack {
                    Label("Downtime", systemImage: "moon.stars.fill")
                    Spacer()
                    Image(systemName: featureEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(featureEnabled ? .green : .secondary)
                }
            }
        } header: {
            Text("Group Setting")
        } footer: {
            if isGroupCreator {
                Text("When enabled, all members configure their own nightly downtime window. You can toggle this anytime without affecting personal schedules.")
            } else {
                Text("Your group creator controls whether downtime is active.")
            }
        }
    }

    // MARK: - Schedule section

    private var scheduleSection: some View {
        Section {
            Toggle("Enable Downtime", isOn: $schedule.enabled)

            if schedule.enabled {
                HStack {
                    Text("Start")
                    Spacer()
                    TimePicker(hour: $schedule.startHour, minute: $schedule.startMinute)
                }
                HStack {
                    Text("End")
                    Spacer()
                    TimePicker(hour: $schedule.endHour, minute: $schedule.endMinute)
                }
            }
        } header: {
            Text("Your Downtime Window")
        } footer: {
            Text("Apps will be blocked each night between these times. Your group sees that you have downtime configured.")
        }
    }

    // MARK: - Allowed apps section

    private var allowedAppsSection: some View {
        Section {
            if AuthorizationCenter.shared.authorizationStatus == .approved {
                Button {
                    showAppPicker = true
                } label: {
                    HStack {
                        Label("Choose Allowed Apps", systemImage: "apps.iphone")
                        Spacer()
                        if !allowedApps.applicationTokens.isEmpty {
                            Text("\(allowedApps.applicationTokens.count) selected")
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
            Text("Apps Allowed During Downtime")
        } footer: {
            Text("These apps stay unblocked during your downtime window. Leave empty to block everything.")
        }
    }

    // MARK: - Override requests (incoming — other members requesting approval)

    private var overrideSection: some View {
        Section("Override Requests") {
            ForEach(overrideRequests.filter { $0.requestorUID != currentUID }) { request in
                OverrideRequestRow(
                    request: request,
                    currentUID: currentUID,
                    onRespond: { approved in
                        Task { await respond(to: request, approved: approved) }
                    }
                )
            }
        }
    }

    // MARK: - My override request

    private var requestOverrideSection: some View {
        Section {
            if let myRequest = overrideRequests.first(where: { $0.requestorUID == currentUID && $0.status == .pending }) {
                HStack {
                    Label("Override pending…", systemImage: "clock.badge.questionmark")
                    Spacer()
                    Text(myRequest.durationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if overrideRequests.first(where: { $0.requestorUID == currentUID && $0.status == .approved && !$0.isExpired }) != nil {
                Label("Override active", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    showOverrideSheet = true
                } label: {
                    Label("Request Override", systemImage: "person.badge.key.fill")
                }
                .sheet(isPresented: $showOverrideSheet) {
                    RequestOverrideSheet(groupID: groupID, requestorUID: currentUID)
                        .presentationDetents([.height(280)])
                }
            }
        } header: {
            Text("Need Access During Downtime?")
        } footer: {
            Text("Someone else must approve your request.")
        }
    }

    // MARK: - Actions

    private func loadSchedule() async {
        do {
            schedule = try await DowntimeService.shared.loadSchedule(uid: currentUID)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveSchedule() async {
        isSaving = true
        defer { isSaving = false }
        saveError = nil

        do {
            try await DowntimeService.shared.saveSchedule(uid: currentUID, schedule: schedule)
            DowntimeService.shared.persistAllowedApps(allowedApps)

            // Apply or stop the repeating DeviceActivity schedule.
            try DowntimeScheduler.startMonitoring(schedule: schedule)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func respond(to request: DowntimeOverrideRequest, approved: Bool) async {
        do {
            try await DowntimeService.shared.respondToOverrideRequest(
                groupID: groupID,
                requestID: request.id,
                approved: approved,
                responderUID: currentUID
            )
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func updateGroupFeature(enabled: Bool) async {
        do {
            try await GroupService.shared.updateGroupSetting(
                groupID: groupID,
                requesterUID: currentUID,
                key: "downtimeEnabled",
                value: enabled
            )
        } catch {
            saveError = error.localizedDescription
            featureEnabled = !enabled
        }
    }

    private func startOverrideListener() {
        // Capture only the group ID and UID to avoid retaining the view struct.
        let gid = groupID
        let uid = currentUID
        let reg = DowntimeService.shared.observeOverrideRequests(groupID: gid) { requests in
            overrideRequests = requests

            // If our own request just got approved, lift shields and schedule re-enable.
            if let mine = requests.first(where: { $0.requestorUID == uid && $0.status == .approved && !$0.isExpired }),
               let expiresAt = mine.expiresAt {
                DowntimeScheduler.suspendForOverride()
                scheduleOverrideExpiry(at: expiresAt, requestID: mine.id)
            }
        }
        // Store as AnyObject to keep the ListenerRegistration alive without typing it explicitly.
        overrideListener = reg as AnyObject
    }

    private func scheduleOverrideExpiry(at expiresAt: Date, requestID: String) {
        overrideExpiryTask?.cancel()
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        let capturedGroupID = groupID
        let capturedSchedule = schedule

        overrideExpiryTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await DowntimeService.shared.expireOverrideRequestIfNeeded(groupID: capturedGroupID, requestID: requestID)
            try? DowntimeScheduler.resumeAfterOverride(schedule: capturedSchedule)
        }
    }
}

// MARK: - Supporting views

/// Compact hour/minute picker rendered as two inline date pickers sharing one row.
private struct TimePicker: View {
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

/// Single row for an incoming override request showing approve/deny buttons.
private struct OverrideRequestRow: View {
    let request: DowntimeOverrideRequest
    let currentUID: String
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Override request · \(request.durationLabel)", systemImage: "person.badge.key")
                Spacer()
                statusBadge
            }

            if request.status == .pending, request.requestorUID != currentUID {
                HStack(spacing: 12) {
                    Button("Deny") { onRespond(false) }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    Button("Approve") { onRespond(true) }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch request.status {
        case .pending:
            Text("Pending")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        case .approved:
            Text("Approved")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .denied:
            Text("Denied")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
        case .expired:
            Text("Expired")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// Sheet that lets the user pick a duration and submit an override request.
private struct RequestOverrideSheet: View {
    let groupID: String
    let requestorUID: String

    @State private var selectedMinutes: Int = 15
    @State private var customMinutes: Int = 30
    @State private var useCustom = false
    @State private var isSubmitting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private let presets = [1, 5, 15, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    ForEach(presets, id: \.self) { minutes in
                        Button {
                            selectedMinutes = minutes
                            useCustom = false
                        } label: {
                            HStack {
                                Text(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                                Spacer()
                                if !useCustom && selectedMinutes == minutes {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    HStack {
                        Button {
                            useCustom = true
                        } label: {
                            HStack {
                                Text("Custom")
                                Spacer()
                                if useCustom {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        if useCustom {
                            Stepper("\(customMinutes) min", value: $customMinutes, in: 1...120)
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .kawaiiListBackground()
            .navigationTitle("Request Override")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") { Task { await submit() } }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        error = nil

        let duration = useCustom ? customMinutes : selectedMinutes
        do {
            try await DowntimeService.shared.submitOverrideRequest(
                groupID: groupID,
                requestorUID: requestorUID,
                durationMinutes: duration
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
