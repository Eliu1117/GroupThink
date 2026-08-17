//
//  DurationWheelPicker.swift
//  Screen time demo
//
//  Clock-app-style countdown wheels: hours + minutes.
//

import SwiftUI

struct DurationWheelPicker: View {
    @Binding var totalMinutes: Int
    var isEnabled: Bool = true
    var maxHours: Int = 23
    var wheelHeight: CGFloat = 148
    var valueFontSize: CGFloat = 22

    private var valueFont: Font { .theme.heading(valueFontSize) }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { min(maxHours, totalMinutes / 60) },
            set: { newHours in
                let clampedHours = min(max(0, newHours), maxHours)
                totalMinutes = clampedHours * 60 + (totalMinutes % 60)
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { totalMinutes % 60 },
            set: { newMinutes in
                let clampedMinutes = min(max(0, newMinutes), 59)
                totalMinutes = (totalMinutes / 60) * 60 + clampedMinutes
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Hours", selection: hourBinding) {
                ForEach(0...maxHours, id: \.self) { value in
                    Text("\(value)")
                        .font(valueFont)
                        .foregroundStyle(Color.theme.text)
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel("Hours")

            Text("hours")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text)
                .padding(.trailing, 4)

            Picker("Minutes", selection: minuteBinding) {
                ForEach(0..<60, id: \.self) { value in
                    Text(String(format: "%02d", value))
                        .font(valueFont)
                        .foregroundStyle(Color.theme.text)
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel("Minutes")

            Text("min")
                .font(.theme.body())
                .foregroundStyle(Color.theme.text)
                .padding(.trailing, 8)
        }
        .frame(height: wheelHeight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Single-column wheel picker for small integer ranges (session counts, break minutes, etc.).
struct WheelIntPicker: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String = ""
    var isEnabled: Bool = true
    var wheelHeight: CGFloat = 110
    var valueFontSize: CGFloat = 18

    private var valueFont: Font { .theme.heading(valueFontSize) }

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: $value) {
                ForEach(Array(range), id: \.self) { number in
                    Text("\(number)")
                        .font(valueFont)
                        .foregroundStyle(Color.theme.text)
                        .tag(number)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel(suffix.isEmpty ? "Value" : suffix)

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.theme.body())
                    .foregroundStyle(Color.theme.text)
                    .padding(.trailing, 8)
            }
        }
        .frame(height: wheelHeight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

extension Int {
    var durationPhrase: String {
        let hours = self / 60
        let minutes = self % 60
        switch (hours, minutes) {
        case (0, 0):
            return "0 min"
        case (0, _):
            return "\(minutes) min"
        case (_, 0):
            return "\(hours) hr"
        default:
            return "\(hours) hr \(minutes) min"
        }
    }
}
