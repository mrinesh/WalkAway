//
//  BreakScheduler.swift
//  WalkAway
//

import Foundation

/// The work-timer state machine. It owns no timers and reads no system state:
/// callers feed it elapsed time, the wall clock, and idle info, so it can be tested with a fake clock.
struct BreakScheduler {
    struct Configuration: Equatable {
        /// Work time between breaks.
        var workInterval: TimeInterval
        /// Idle this long and the cycle resets.
        var awayThreshold: TimeInterval
        /// Idle this long and the countdown freezes, so a break never fires at an empty desk.
        var idleGrace: TimeInterval = 60
        /// Screen off (saver, lock, sleep) this long counts as a break.
        var screenOffResetDelay: TimeInterval = 10
        /// How long before a break the heads-up is shown.
        var warningLead: TimeInterval = 30
        /// Idle below this while away means the user is back.
        var returnIdleTolerance: TimeInterval = 2
        /// Caps a single tick so a stalled run loop can't jump the countdown.
        var maxTickStep: TimeInterval = 5
    }

    struct Inputs {
        var idleSeconds: TimeInterval
        var isVideoPlaying = false
        var isInMeeting = false
        var isManuallyPaused = false
    }

    enum Phase: Equatable {
        case working, onBreak, away
    }

    enum Event: Equatable {
        case warning, breakDue, wentAway, returned
    }

    var configuration: Configuration
    private(set) var phase: Phase = .working
    private(set) var remaining: TimeInterval
    private(set) var screenOffSince: TimeInterval?
    private var hasWarned = false

    init(configuration: Configuration) {
        self.configuration = configuration
        remaining = configuration.workInterval
    }

    /// Starts a fresh work interval without changing phase.
    mutating func resetCycle() {
        remaining = configuration.workInterval
        hasWarned = false
    }

    mutating func finishBreak() {
        guard phase == .onBreak else { return }
        phase = .working
        resetCycle()
    }

    /// `now` is wall-clock time, so time spent asleep counts.
    mutating func screenDidTurnOff(at now: TimeInterval) {
        if screenOffSince == nil {
            screenOffSince = now
        }
    }

    mutating func screenDidTurnOn(at now: TimeInterval) -> [Event] {
        guard let since = screenOffSince else { return [] }
        screenOffSince = nil
        return now - since >= configuration.screenOffResetDelay ? goAway() : []
    }

    /// `elapsed` should come from a monotonic clock; `now` is wall-clock time.
    mutating func tick(elapsed: TimeInterval, now: TimeInterval, inputs: Inputs) -> [Event] {
        if let since = screenOffSince {
            return now - since >= configuration.screenOffResetDelay ? goAway() : []
        }
        if inputs.isManuallyPaused { return [] }

        switch phase {
        case .onBreak:
            return []

        case .away:
            guard inputs.idleSeconds < configuration.returnIdleTolerance else { return [] }
            phase = .working
            return [.returned]

        case .working:
            if inputs.isInMeeting { return [] }
            if !inputs.isVideoPlaying {
                if inputs.idleSeconds >= configuration.awayThreshold { return goAway() }
                if inputs.idleSeconds >= configuration.idleGrace { return [] }
            }
            return countDown(by: min(max(elapsed, 0), configuration.maxTickStep))
        }
    }

    private mutating func countDown(by step: TimeInterval) -> [Event] {
        remaining = max(0, remaining - step)
        var events: [Event] = []
        if !hasWarned && remaining <= configuration.warningLead {
            hasWarned = true
            events.append(.warning)
        }
        if remaining <= 0 {
            phase = .onBreak
            events.append(.breakDue)
        }
        return events
    }

    private mutating func goAway() -> [Event] {
        guard phase != .away else { return [] }
        phase = .away
        resetCycle()
        return [.wentAway]
    }
}
