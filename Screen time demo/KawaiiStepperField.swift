//
//  KawaiiStepperField.swift
//  Screen time demo
//
//  Minimalist "- / value / +" stepper with tap-to-edit numeric entry, replacing the bulky
//  inline `WheelIntPicker` scroll wheels on the Pomodoro settings card. Uses the current
//  theme's primary color for the active +/- buttons, so it stays in sync with whichever
//  `AppTheme` the user has selected rather than a hardcoded color.
//

import SwiftUI

struct KawaiiStepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String = ""

    // `value`/`range`/`step`/`suffix` are all independent of the color theme, so without a
    // real subscription here SwiftUI can decide nothing about this view "changed" on a theme
    // switch and skip re-rendering its `Color.theme.*`-based styling — see `KawaiiCardModifier`.
    @ObservedObject private var themeSettings = ThemeSettings.shared

    @State private var isEditing = false
    @State private var draftText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            stepperButton(systemImage: "minus", enabled: value > range.lowerBound, action: decrement)

            Spacer(minLength: 0)

            valueField
                .frame(minWidth: 76)

            Spacer(minLength: 0)

            stepperButton(systemImage: "plus", enabled: value < range.upperBound, action: increment)
        }
        .onChange(of: fieldFocused) { _, focused in
            if !focused, isEditing { commitDraft() }
        }
    }

    // MARK: - Value / tap-to-edit

    @ViewBuilder
    private var valueField: some View {
        if isEditing {
            TextField("", text: $draftText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($fieldFocused)
                .font(.theme.heading(20))
                .foregroundStyle(Color.theme.text)
                .onSubmit(commitDraft)
        } else {
            Button {
                draftText = "\(value)"
                isEditing = true
                fieldFocused = true
            } label: {
                HStack(spacing: 4) {
                    Text("\(value)")
                        .font(.theme.heading(20))
                        .foregroundStyle(Color.theme.text)
                        .contentTransition(.numericText())
                    if !suffix.isEmpty {
                        Text(suffix)
                            .font(.theme.body())
                            .foregroundStyle(Color.theme.text.opacity(0.55))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stepper buttons

    private func stepperButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? Color.theme.text : Color.theme.text.opacity(0.3))
                .frame(width: 34, height: 34)
                .background(Color.theme.primary.opacity(enabled ? 0.35 : 0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func increment() {
        withAnimation(.snappy(duration: 0.15)) {
            value = min(range.upperBound, value + step)
        }
    }

    private func decrement() {
        withAnimation(.snappy(duration: 0.15)) {
            value = max(range.lowerBound, value - step)
        }
    }

    private func commitDraft() {
        isEditing = false
        guard let parsed = Int(draftText) else { return }
        value = min(range.upperBound, max(range.lowerBound, parsed))
    }
}
