//
//  PomodoroManager.swift
//  boringNotch
//
//  Persistent focus timer state and system integration.
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Combine
import Defaults
import SwiftUI
import UserNotifications

enum PomodoroPhase: String, Codable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: String(localized: "Focus")
        case .shortBreak: String(localized: "Short break")
        case .longBreak: String(localized: "Long break")
        }
    }

    var icon: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }

    var tint: Color {
        switch self {
        case .focus: .orange
        case .shortBreak: .green
        case .longBreak: .teal
        }
    }
}

struct PomodoroDurations: Equatable {
    var focus: TimeInterval
    var shortBreak: TimeInterval
    var longBreak: TimeInterval

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

struct PomodoroTimerConfiguration: Equatable {
    var durations: PomodoroDurations
    var sessionsBeforeLongBreak: Int
    var autoStartNext: Bool
}

struct PomodoroSessionRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var completedAt: Date
    var plannedDuration: TimeInterval

    init(
        id: UUID = UUID(),
        completedAt: Date,
        plannedDuration: TimeInterval
    ) {
        self.id = id
        self.completedAt = completedAt
        self.plannedDuration = plannedDuration
    }
}

/// Codable, deterministic timer state. Keeping the transition logic here
/// makes sleep/relaunch behavior testable without starting an AppKit app.
struct PomodoroTimerState: Codable, Equatable {
    var phase: PomodoroPhase
    var isRunning: Bool
    var remaining: TimeInterval
    var sessionDuration: TimeInterval
    var endDate: Date?
    var completedFocusSessions: Int
    var history: [PomodoroSessionRecord]

    init(configuration: PomodoroTimerConfiguration) {
        phase = .focus
        isRunning = false
        sessionDuration = configuration.durations.duration(for: .focus)
        remaining = sessionDuration
        endDate = nil
        completedFocusSessions = 0
        history = []
    }

    var isActive: Bool {
        isRunning || remaining < sessionDuration
    }

    var progress: Double {
        guard sessionDuration > 0 else { return 0 }
        return min(max(1 - remaining / sessionDuration, 0), 1)
    }

    mutating func start(at date: Date) {
        guard !isRunning else { return }
        remaining = max(0, remaining)
        endDate = date.addingTimeInterval(remaining)
        isRunning = true
    }

    mutating func pause(at date: Date) {
        guard isRunning else { return }
        if let endDate {
            remaining = max(0, endDate.timeIntervalSince(date))
        }
        isRunning = false
        endDate = nil
    }

    mutating func reset(configuration: PomodoroTimerConfiguration) {
        phase = .focus
        isRunning = false
        sessionDuration = configuration.durations.duration(for: .focus)
        remaining = sessionDuration
        endDate = nil
        completedFocusSessions = 0
    }

    mutating func skip(at date: Date, configuration: PomodoroTimerConfiguration) {
        let shouldResume = isRunning
        isRunning = false
        endDate = nil
        moveToNextPhase(countingCompletion: false, at: date, configuration: configuration)
        if shouldResume { start(at: date) }
    }

    /// Reconciles the countdown against wall-clock time. This is called by
    /// the ticker and after relaunch, so sleep never stretches a session.
    /// Returns every phase that completed while the process was inactive.
    mutating func reconcile(
        at date: Date,
        configuration: PomodoroTimerConfiguration
    ) -> [PomodoroPhase] {
        guard isRunning, var deadline = endDate else { return [] }

        if deadline > date {
            remaining = max(0, deadline.timeIntervalSince(date))
            return []
        }

        var finishedPhases: [PomodoroPhase] = []
        // A cap prevents a corrupted date or very long absence with automatic
        // continuation from generating unbounded history during launch.
        for _ in 0..<512 {
            let finished = phase
            finishedPhases.append(finished)
            moveToNextPhase(
                countingCompletion: true,
                at: deadline,
                configuration: configuration
            )

            guard configuration.autoStartNext else {
                isRunning = false
                endDate = nil
                return finishedPhases
            }

            deadline = deadline.addingTimeInterval(sessionDuration)
            endDate = deadline
            isRunning = true
            remaining = max(0, deadline.timeIntervalSince(date))
            if deadline > date { return finishedPhases }
        }

        isRunning = false
        endDate = nil
        remaining = sessionDuration
        return finishedPhases
    }

    mutating func refreshIdleDuration(configuration: PomodoroTimerConfiguration) {
        guard !isActive else { return }
        sessionDuration = configuration.durations.duration(for: phase)
        remaining = sessionDuration
    }

    mutating func clearHistory() {
        history = []
    }

    func completedFocusSessions(on date: Date, calendar: Calendar = .current) -> Int {
        history.lazy.filter { calendar.isDate($0.completedAt, inSameDayAs: date) }.count
    }

    private mutating func moveToNextPhase(
        countingCompletion: Bool,
        at completionDate: Date,
        configuration: PomodoroTimerConfiguration
    ) {
        let nextPhase: PomodoroPhase
        switch phase {
        case .focus:
            if countingCompletion {
                completedFocusSessions += 1
                history.append(
                    PomodoroSessionRecord(
                        completedAt: completionDate,
                        plannedDuration: sessionDuration
                    )
                )
                trimHistory(relativeTo: completionDate)
            }
            let interval = max(1, configuration.sessionsBeforeLongBreak)
            nextPhase = completedFocusSessions >= interval ? .longBreak : .shortBreak
        case .shortBreak:
            nextPhase = .focus
        case .longBreak:
            completedFocusSessions = 0
            nextPhase = .focus
        }

        phase = nextPhase
        sessionDuration = configuration.durations.duration(for: nextPhase)
        remaining = sessionDuration
        endDate = nil
    }

    private mutating func trimHistory(relativeTo date: Date) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: date) else { return }
        history.removeAll { $0.completedAt < cutoff }
    }
}

protocol PomodoroStateStoring {
    func load() -> PomodoroTimerState?
    func save(_ state: PomodoroTimerState)
}

struct UserDefaultsPomodoroStateStore: PomodoroStateStoring {
    static let stateKey = "focusNotch.pomodoro.state.v1"

    var defaults: UserDefaults = .standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> PomodoroTimerState? {
        guard let data = defaults.data(forKey: Self.stateKey) else { return nil }
        return try? decoder.decode(PomodoroTimerState.self, from: data)
    }

    func save(_ state: PomodoroTimerState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private var state: PomodoroTimerState

    private let store: PomodoroStateStoring
    private let notificationCenter: UNUserNotificationCenter
    private var ticker: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private static let notificationIdentifier = "focusnotch.pomodoro.phase-end"

    private init(
        store: PomodoroStateStoring = UserDefaultsPomodoroStateStore(),
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.store = store
        self.notificationCenter = notificationCenter

        let configuration = Self.configuration
        var restored = store.load() ?? PomodoroTimerState(configuration: configuration)
        _ = restored.reconcile(at: Date(), configuration: configuration)
        restored.refreshIdleDuration(configuration: configuration)
        state = restored
        store.save(restored)

        Defaults.publisher(
            keys: .pomodoroFocusMinutes,
            .pomodoroShortBreakMinutes,
            .pomodoroLongBreakMinutes,
            options: []
        )
        .sink { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                var updated = self.state
                updated.refreshIdleDuration(configuration: Self.configuration)
                guard updated != self.state else { return }
                self.state = updated
                self.persist()
            }
        }
        .store(in: &cancellables)

        if state.isRunning {
            startTicker()
            schedulePhaseEndNotification()
        }
    }

    var phase: PomodoroPhase { state.phase }
    var isRunning: Bool { state.isRunning }
    var remaining: TimeInterval { state.remaining }
    var completedFocusSessions: Int { state.completedFocusSessions }
    var history: [PomodoroSessionRecord] { state.history }
    var totalDuration: TimeInterval { state.sessionDuration }
    var isActive: Bool { state.isActive }
    var progress: Double { state.progress }
    var todayCompletedFocusSessions: Int { state.completedFocusSessions(on: Date()) }

    var formattedRemaining: String {
        let seconds = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static var configuration: PomodoroTimerConfiguration {
        PomodoroTimerConfiguration(
            durations: PomodoroDurations(
                focus: TimeInterval(max(1, Defaults[.pomodoroFocusMinutes]) * 60),
                shortBreak: TimeInterval(max(1, Defaults[.pomodoroShortBreakMinutes]) * 60),
                longBreak: TimeInterval(max(1, Defaults[.pomodoroLongBreakMinutes]) * 60)
            ),
            sessionsBeforeLongBreak: max(1, Defaults[.pomodoroSessionsBeforeLongBreak]),
            autoStartNext: Defaults[.pomodoroAutoStartNext]
        )
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !state.isRunning else { return }
        state.start(at: Date())
        persist()
        startTicker()
        requestNotificationAuthorizationIfNeeded()
        schedulePhaseEndNotification()
    }

    func pause() {
        guard state.isRunning else { return }
        updateState(at: Date(), announceCompletions: true)
        guard state.isRunning else { return }
        state.pause(at: Date())
        ticker?.cancel()
        ticker = nil
        cancelPhaseEndNotification()
        persist()
    }

    func reset() {
        ticker?.cancel()
        ticker = nil
        state.reset(configuration: Self.configuration)
        cancelPhaseEndNotification()
        persist()
    }

    func skip() {
        let shouldResume = state.isRunning
        ticker?.cancel()
        ticker = nil
        state.skip(at: Date(), configuration: Self.configuration)
        cancelPhaseEndNotification()
        persist()
        if shouldResume {
            startTicker()
            schedulePhaseEndNotification()
        }
    }

    func clearHistory() {
        state.clearHistory()
        persist()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateState(at: Date(), announceCompletions: true)
                if !self.state.isRunning { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func updateState(at date: Date, announceCompletions: Bool) {
        var updated = state
        let finished = updated.reconcile(at: date, configuration: Self.configuration)

        let oldDisplayedSecond = Int(state.remaining.rounded(.up))
        let newDisplayedSecond = Int(updated.remaining.rounded(.up))
        guard updated != state else { return }
        guard !finished.isEmpty || oldDisplayedSecond != newDisplayedSecond else { return }
        state = updated

        guard !finished.isEmpty else { return }
        persist()
        if announceCompletions {
            finished.forEach(announce)
        }
        if state.isRunning {
            schedulePhaseEndNotification()
        } else {
            ticker?.cancel()
            ticker = nil
            cancelPhaseEndNotification()
        }
    }

    private func persist() {
        store.save(state)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard Defaults[.pomodoroNotificationsEnabled] else { return }
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func schedulePhaseEndNotification() {
        cancelPhaseEndNotification()
        guard Defaults[.pomodoroNotificationsEnabled],
              state.isRunning,
              let endDate = state.endDate
        else { return }

        let content = UNMutableNotificationContent()
        content.title = phase == .focus
            ? String(localized: "Focus session complete")
            : String(localized: "Break complete")
        content.body = phase == .focus
            ? String(localized: "Time for a break.")
            : String(localized: "Ready for another focus session?")
        if Defaults[.pomodoroPlaySound] {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, endDate.timeIntervalSinceNow),
            repeats: false
        )
        notificationCenter.add(
            UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: trigger
            )
        )
    }

    private func cancelPhaseEndNotification() {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier]
        )
    }

    private func announce(_ finished: PomodoroPhase) {
        if Defaults[.pomodoroPlaySound] {
            NSSound(named: finished == .focus ? "Glass" : "Hero")?.play()
        }
        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if Defaults[.pomodoroShowInClosedNotch] {
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .pomodoro)
        }
    }
}
