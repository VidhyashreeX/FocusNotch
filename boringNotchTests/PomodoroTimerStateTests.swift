//
//  PomodoroTimerStateTests.swift
//  boringNotchTests
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Foundation
import XCTest
@testable import boringNotch

final class PomodoroTimerStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func configuration(
        focus: TimeInterval = 100,
        shortBreak: TimeInterval = 20,
        longBreak: TimeInterval = 40,
        sessionsBeforeLongBreak: Int = 2,
        autoStartNext: Bool = false
    ) -> PomodoroTimerConfiguration {
        PomodoroTimerConfiguration(
            durations: PomodoroDurations(
                focus: focus,
                shortBreak: shortBreak,
                longBreak: longBreak
            ),
            sessionsBeforeLongBreak: sessionsBeforeLongBreak,
            autoStartNext: autoStartNext
        )
    }

    func testStartPauseAndResumeUseWallClockTime() {
        let configuration = configuration()
        var state = PomodoroTimerState(configuration: configuration)

        state.start(at: start)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.endDate, start.addingTimeInterval(100))

        state.pause(at: start.addingTimeInterval(30))
        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.endDate)
        XCTAssertEqual(state.remaining, 70, accuracy: 0.001)

        state.start(at: start.addingTimeInterval(50))
        XCTAssertEqual(state.endDate, start.addingTimeInterval(120))
    }

    func testResetReturnsToFreshFocusButPreservesHistory() {
        let configuration = configuration()
        var state = PomodoroTimerState(configuration: configuration)
        state.history = [
            PomodoroSessionRecord(completedAt: start, plannedDuration: 100)
        ]
        state.start(at: start)
        state.pause(at: start.addingTimeInterval(25))

        state.reset(configuration: configuration)

        XCTAssertEqual(state.phase, .focus)
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.remaining, 100)
        XCTAssertEqual(state.completedFocusSessions, 0)
        XCTAssertEqual(state.history.count, 1)
    }

    func testCompletedFocusMovesToShortBreakAndAddsHistory() {
        let configuration = configuration(sessionsBeforeLongBreak: 4)
        var state = PomodoroTimerState(configuration: configuration)
        state.start(at: start)

        let completed = state.reconcile(
            at: start.addingTimeInterval(100),
            configuration: configuration
        )

        XCTAssertEqual(completed, [.focus])
        XCTAssertEqual(state.phase, .shortBreak)
        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.remaining, 20)
        XCTAssertEqual(state.completedFocusSessions, 1)
        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history.first?.completedAt, start.addingTimeInterval(100))
    }

    func testLongBreakStartsAfterConfiguredNumberOfFocusSessions() {
        let configuration = configuration(sessionsBeforeLongBreak: 2)
        var state = PomodoroTimerState(configuration: configuration)

        state.start(at: start)
        _ = state.reconcile(at: start.addingTimeInterval(100), configuration: configuration)
        state.start(at: start.addingTimeInterval(100))
        _ = state.reconcile(at: start.addingTimeInterval(120), configuration: configuration)
        state.start(at: start.addingTimeInterval(120))
        _ = state.reconcile(at: start.addingTimeInterval(220), configuration: configuration)

        XCTAssertEqual(state.phase, .longBreak)
        XCTAssertEqual(state.remaining, 40)
        XCTAssertEqual(state.completedFocusSessions, 2)
        XCTAssertEqual(state.history.count, 2)

        state.start(at: start.addingTimeInterval(220))
        _ = state.reconcile(at: start.addingTimeInterval(260), configuration: configuration)
        XCTAssertEqual(state.phase, .focus)
        XCTAssertEqual(state.completedFocusSessions, 0)
    }

    func testSkipDoesNotCountAFocusSessionAndKeepsRunningState() {
        let configuration = configuration()
        var state = PomodoroTimerState(configuration: configuration)
        state.start(at: start)

        state.skip(at: start.addingTimeInterval(10), configuration: configuration)

        XCTAssertEqual(state.phase, .shortBreak)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.completedFocusSessions, 0)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(state.endDate, start.addingTimeInterval(30))
    }

    func testAutoStartReconcilesEveryPhaseElapsedDuringSleep() {
        let configuration = configuration(
            focus: 10,
            shortBreak: 5,
            longBreak: 20,
            sessionsBeforeLongBreak: 4,
            autoStartNext: true
        )
        var state = PomodoroTimerState(configuration: configuration)
        state.start(at: start)

        let completed = state.reconcile(
            at: start.addingTimeInterval(27),
            configuration: configuration
        )

        XCTAssertEqual(completed, [.focus, .shortBreak, .focus])
        XCTAssertEqual(state.phase, .shortBreak)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.remaining, 3, accuracy: 0.001)
        XCTAssertEqual(state.history.count, 2)
    }

    func testCodableRoundTripRestoresRunningDeadline() throws {
        let configuration = configuration()
        var original = PomodoroTimerState(configuration: configuration)
        original.start(at: start)

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(PomodoroTimerState.self, from: data)
        let completed = restored.reconcile(
            at: start.addingTimeInterval(35),
            configuration: configuration
        )

        XCTAssertTrue(completed.isEmpty)
        XCTAssertTrue(restored.isRunning)
        XCTAssertEqual(restored.remaining, 65, accuracy: 0.001)
    }

    func testDailyCountUsesOnlyRequestedCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let configuration = configuration()
        var state = PomodoroTimerState(configuration: configuration)
        state.history = [
            PomodoroSessionRecord(completedAt: start, plannedDuration: 100),
            PomodoroSessionRecord(completedAt: start.addingTimeInterval(60), plannedDuration: 100),
            PomodoroSessionRecord(completedAt: start.addingTimeInterval(86_400), plannedDuration: 100)
        ]

        XCTAssertEqual(state.completedFocusSessions(on: start, calendar: calendar), 2)
        XCTAssertEqual(
            state.completedFocusSessions(on: start.addingTimeInterval(86_400), calendar: calendar),
            1
        )
    }
}
