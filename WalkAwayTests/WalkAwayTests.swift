//
//  WalkAwayTests.swift
//  WalkAwayTests
//
//  Created by rinesh on 04/04/25.
//

import Testing
@testable import WalkAway

@Suite("BreakScheduler")
struct BreakSchedulerTests {
    // F = 30 min, T = 10 min, G = 60 s, screen-off reset = 10 s, warning = 30 s
    private func makeScheduler() -> BreakScheduler {
        BreakScheduler(configuration: .init(workInterval: 1800, awayThreshold: 600))
    }

    private let active = BreakScheduler.Inputs(idleSeconds: 0)

    /// Ticks once per second for `seconds`, starting the wall clock at `start`.
    @discardableResult
    private func run(_ scheduler: inout BreakScheduler, seconds: Int, inputs: BreakScheduler.Inputs, start: Double = 0) -> [BreakScheduler.Event] {
        (1...seconds).flatMap { scheduler.tick(elapsed: 1, now: start + Double($0), inputs: inputs) }
    }

    @Test func countsDownWhileActive() {
        var scheduler = makeScheduler()
        run(&scheduler, seconds: 120, inputs: active)
        #expect(scheduler.remaining == 1680)
        #expect(scheduler.phase == .working)
    }

    @Test func freezesAfterShortIdle() {
        var scheduler = makeScheduler()
        run(&scheduler, seconds: 100, inputs: .init(idleSeconds: 59))
        #expect(scheduler.remaining == 1700)
        run(&scheduler, seconds: 100, inputs: .init(idleSeconds: 60))
        #expect(scheduler.remaining == 1700)
    }

    @Test func resetsAfterAwayThresholdAndStaysResetUntilInput() {
        var scheduler = makeScheduler()
        run(&scheduler, seconds: 600, inputs: active)
        #expect(scheduler.remaining == 1200)

        let events = scheduler.tick(elapsed: 1, now: 601, inputs: .init(idleSeconds: 600))
        #expect(events == [.wentAway])
        #expect(scheduler.phase == .away)
        #expect(scheduler.remaining == 1800)

        // Still away: no repeat events, no countdown
        #expect(run(&scheduler, seconds: 300, inputs: .init(idleSeconds: 900)).isEmpty)
        #expect(scheduler.remaining == 1800)

        // Input arrives: timer resumes from the full interval
        #expect(scheduler.tick(elapsed: 1, now: 1000, inputs: .init(idleSeconds: 0.5)) == [.returned])
        run(&scheduler, seconds: 10, inputs: active, start: 1000)
        #expect(scheduler.remaining == 1790)
    }

    @Test func watchingVideoCountsAsActivity() {
        var scheduler = makeScheduler()
        let watching = BreakScheduler.Inputs(idleSeconds: 900, isVideoPlaying: true)
        #expect(run(&scheduler, seconds: 300, inputs: watching).isEmpty)
        #expect(scheduler.phase == .working)
        #expect(scheduler.remaining == 1500)
    }

    @Test func idleDuringMeetingDoesNotResetOrCountDown() {
        var scheduler = makeScheduler()
        let inMeeting = BreakScheduler.Inputs(idleSeconds: 900, isInMeeting: true)
        #expect(run(&scheduler, seconds: 300, inputs: inMeeting).isEmpty)
        #expect(scheduler.phase == .working)
        #expect(scheduler.remaining == 1800)
    }

    @Test func briefScreenOffDoesNotReset() {
        var scheduler = makeScheduler()
        run(&scheduler, seconds: 100, inputs: active)
        scheduler.screenDidTurnOff(at: 100)
        #expect(scheduler.screenDidTurnOn(at: 109.9).isEmpty)
        #expect(scheduler.remaining == 1700)
        #expect(scheduler.phase == .working)
    }

    @Test func screenOffForTenSecondsResets() {
        var scheduler = makeScheduler()
        run(&scheduler, seconds: 100, inputs: active)
        scheduler.screenDidTurnOff(at: 100)
        #expect(scheduler.screenDidTurnOn(at: 110) == [.wentAway])
        #expect(scheduler.phase == .away)
        #expect(scheduler.remaining == 1800)
    }

    @Test func screenOffResetsWhileStillOff() {
        var scheduler = makeScheduler()
        scheduler.screenDidTurnOff(at: 0)
        #expect(run(&scheduler, seconds: 9, inputs: active).isEmpty)
        #expect(scheduler.remaining == 1800, "countdown is frozen while the screen is off")
        #expect(scheduler.tick(elapsed: 1, now: 10, inputs: active) == [.wentAway])
    }

    @Test func sleepCountsByWallClock() {
        // The tick timer doesn't fire during sleep; the reset is decided when the screen comes back
        var scheduler = makeScheduler()
        scheduler.screenDidTurnOff(at: 0)
        #expect(scheduler.screenDidTurnOn(at: 8 * 3600) == [.wentAway])
    }

    @Test func warnsOnceThenBreaks() {
        var scheduler = makeScheduler()
        let events = run(&scheduler, seconds: 1800, inputs: active)
        #expect(events == [.warning, .breakDue])
        #expect(scheduler.phase == .onBreak)

        #expect(run(&scheduler, seconds: 60, inputs: active).isEmpty, "nothing happens during the break")
        scheduler.finishBreak()
        #expect(scheduler.phase == .working)
        #expect(scheduler.remaining == 1800)
    }

    @Test func screenOffDuringBreakEndsIt() {
        var scheduler = makeScheduler()
        run(&scheduler, seconds: 1800, inputs: active)
        scheduler.screenDidTurnOff(at: 1800)
        #expect(scheduler.screenDidTurnOn(at: 1900) == [.wentAway])
        #expect(scheduler.phase == .away)
    }

    @Test func manualPauseFreezesButScreenOffStillResets() {
        var scheduler = makeScheduler()
        run(&scheduler, seconds: 100, inputs: active)
        let paused = BreakScheduler.Inputs(idleSeconds: 900, isManuallyPaused: true)
        #expect(run(&scheduler, seconds: 300, inputs: paused, start: 100).isEmpty)
        #expect(scheduler.remaining == 1700)

        scheduler.screenDidTurnOff(at: 400)
        #expect(scheduler.screenDidTurnOn(at: 500) == [.wentAway])
        #expect(scheduler.remaining == 1800)
    }

    @Test func largeElapsedIsCapped() {
        var scheduler = makeScheduler()
        _ = scheduler.tick(elapsed: 3600, now: 1, inputs: active)
        #expect(scheduler.remaining == 1795)
    }

    @Test func resetCycleRearmsWarning() {
        var scheduler = makeScheduler()
        let first = run(&scheduler, seconds: 1780, inputs: active)
        #expect(first == [.warning])
        scheduler.resetCycle()
        let second = run(&scheduler, seconds: 1780, inputs: active, start: 2000)
        #expect(second == [.warning])
    }
}
