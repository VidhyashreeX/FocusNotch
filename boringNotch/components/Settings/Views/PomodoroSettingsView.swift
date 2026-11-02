//
//  PomodoroSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Defaults
import SwiftUI

struct PomodoroSettingsView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared
    @Default(.enablePomodoro) var enablePomodoro
    @Default(.pomodoroFocusMinutes) var focusMinutes
    @Default(.pomodoroShortBreakMinutes) var shortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) var longBreakMinutes
    @Default(.pomodoroSessionsBeforeLongBreak) var sessionsBeforeLongBreak

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enablePomodoro) {
                    Text("Enable focus timer")
                }
                Defaults.Toggle(key: .pomodoroShowInClosedNotch) {
                    Text("Show countdown in closed notch")
                }
                .disabled(!enablePomodoro)
                Defaults.Toggle(key: .pomodoroNotificationsEnabled) {
                    Text("Notify when a phase ends")
                }
                .disabled(!enablePomodoro)
            } header: {
                Text("General")
            } footer: {
                Text(
                    "Adds a Timer tab to the open notch. A running timer also appears in the closed-notch activity stack.",
                    comment: "Footer explaining where the focus timer appears."
                )
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            Section {
                Stepper(value: $focusMinutes, in: 1...120) {
                    Text("Focus: \(focusMinutes) min")
                }
                Stepper(value: $shortBreakMinutes, in: 1...60) {
                    Text("Short break: \(shortBreakMinutes) min")
                }
                Stepper(value: $longBreakMinutes, in: 1...90) {
                    Text("Long break: \(longBreakMinutes) min")
                }
                Stepper(value: $sessionsBeforeLongBreak, in: 1...12) {
                    Text("Long break after \(sessionsBeforeLongBreak) sessions")
                }
            } header: {
                Text("Durations")
            }
            .disabled(!enablePomodoro)

            Section {
                Defaults.Toggle(key: .pomodoroAutoStartNext) {
                    Text("Automatically start the next phase")
                }
                Defaults.Toggle(key: .pomodoroPlaySound) {
                    Text("Play a sound when a phase ends")
                }
            } header: {
                Text("Behavior")
            }
            .disabled(!enablePomodoro)

            Section {
                LabeledContent("Focus sessions today") {
                    Text("\(pomodoro.todayCompletedFocusSessions)")
                        .monospacedDigit()
                }
                LabeledContent("Saved focus sessions") {
                    Text("\(pomodoro.history.count)")
                        .monospacedDigit()
                }
                Button("Clear focus history", role: .destructive) {
                    pomodoro.clearHistory()
                }
                .disabled(pomodoro.history.isEmpty)
            } header: {
                Text("History")
            } footer: {
                Text("Focus history is stored locally and retained for 90 days.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Timer")
    }
}
