import Foundation
import Darwin

// Minimal test harness. XCTest is not shipped with the Command Line Tools on
// this machine, so the core logic is exercised directly through a standalone
// executable built by `make test`.

private var checks = 0
private var failures = 0

private func check(_ condition: Bool,
                   _ message: @autoclosure () -> String,
                   file: StaticString = #file,
                   line: UInt = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL \(file):\(line): \(message())")
    }
}

private func checkEqual<T: Equatable>(_ actual: T,
                                      _ expected: T,
                                      _ label: String = "",
                                      file: StaticString = #file,
                                      line: UInt = #line) {
    check(actual == expected,
          "\(label) expected \(expected), got \(actual)",
          file: file,
          line: line)
}

private func checkEqual(_ actual: Double,
                        _ expected: Double,
                        accuracy: Double,
                        _ label: String = "",
                        file: StaticString = #file,
                        line: UInt = #line) {
    check(abs(actual - expected) <= accuracy,
          "\(label) expected \(expected) +/- \(accuracy), got \(actual)",
          file: file,
          line: line)
}

private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int,
                  _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day,
                                       hour: hour, minute: minute, second: second))!
}

private func snapshot(counted: TimeInterval, running: Bool, on date: Date) -> TimerSnapshot {
    TimerSnapshot(dayKey: DailyTimer.dayKey(for: date, calendar: calendar),
                  counted: counted,
                  isRunning: running)
}

// MARK: - Tests

private func testFreshDayStartsFullAndPaused() {
    let now = date(2026, 1, 15, 9, 0)
    let timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    checkEqual(timer.displayText, "480m", "fresh display")
    checkEqual(timer.remaining, 8 * 60 * 60, accuracy: 0.001, "fresh remaining")
    check(!timer.isRunning, "fresh timer should be paused")
    check(!timer.isFinished, "fresh timer should not be finished")
}

private func testSnapshotFromAnotherDayIsDiscarded() {
    let now = date(2026, 1, 15, 0, 0, 1)
    let previousDay = date(2026, 1, 14, 18, 0)
    let old = snapshot(counted: 9000, running: true, on: previousDay)

    let timer = DailyTimer(snapshot: old, now: now, calendar: calendar)

    checkEqual(timer.counted, 0, accuracy: 0.001, "discarded counted")
    check(!timer.isRunning, "should stay paused on a new day")
    checkEqual(timer.displayText, "480m", "discarded display")
}

private func testPausedTimerDoesNotCount() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.tick(now: now.addingTimeInterval(3600), calendar: calendar)

    checkEqual(timer.counted, 0, accuracy: 0.001, "paused counted")
    checkEqual(timer.displayText, "480m", "paused display")
}

private func testResumedTimerCountsElapsedTime() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.setRunning(true, now: now)
    check(timer.isRunning, "timer should be running after resume")

    timer.tick(now: now.addingTimeInterval(1), calendar: calendar)
    checkEqual(timer.counted, 1, accuracy: 0.001, "counted after one second")

    timer.tick(now: now.addingTimeInterval(1.5), calendar: calendar)
    checkEqual(timer.counted, 1.5, accuracy: 0.001, "counted after 1.5 seconds")
}

private func testPauseFreezesCountedTime() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.setRunning(true, now: now)
    timer.tick(now: now.addingTimeInterval(1.5), calendar: calendar)
    timer.setRunning(false, now: now.addingTimeInterval(1.5))
    check(!timer.isRunning, "timer should be paused")

    timer.tick(now: now.addingTimeInterval(120), calendar: calendar)

    checkEqual(timer.counted, 1.5, accuracy: 0.001, "frozen counted")
}

private func testLongGapIsClampedInsteadOfConsumingTheBudget() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.setRunning(true, now: now)
    timer.tick(now: now.addingTimeInterval(3600), calendar: calendar)

    checkEqual(timer.counted, 2, accuracy: 0.001, "clamped counted")
    checkEqual(timer.displayText, "480m", "clamped display")
    check(timer.isRunning, "timer should still be running")
}

private func testSynchronizeAnchorsClockWithoutCountingGap() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.setRunning(true, now: now)
    timer.synchronize(now: now.addingTimeInterval(3600), calendar: calendar)

    checkEqual(timer.counted, 0, accuracy: 0.001, "synchronized counted")
    check(timer.isRunning, "timer should still be running after sync")

    timer.tick(now: now.addingTimeInterval(3601), calendar: calendar)
    checkEqual(timer.counted, 1, accuracy: 0.001, "counted after sync")
}

private func testTimerStopsAtZeroAndCannotResume() {
    let now = date(2026, 1, 15, 9, 0)
    let almostDone = snapshot(counted: 28799, running: true, on: now)
    var timer = DailyTimer(snapshot: almostDone, now: now, calendar: calendar)

    check(timer.isRunning, "restored timer should be running")
    timer.tick(now: now.addingTimeInterval(2), calendar: calendar)

    check(timer.isFinished, "timer should be finished")
    check(!timer.isRunning, "finished timer should stop")
    checkEqual(timer.counted, 28800, accuracy: 0.001, "full counted")
    checkEqual(timer.displayText, "0m", "finished display")

    timer.setRunning(true, now: now.addingTimeInterval(3))
    check(!timer.isRunning, "finished timer must not resume")
}

private func testManualResetRefillsAndPauses() {
    let now = date(2026, 1, 15, 9, 0)
    let saved = snapshot(counted: 100, running: true, on: now)
    var timer = DailyTimer(snapshot: saved, now: now, calendar: calendar)

    timer.reset(now: now.addingTimeInterval(5), calendar: calendar)

    checkEqual(timer.counted, 0, accuracy: 0.001, "reset counted")
    check(!timer.isRunning, "reset timer should be paused")
    checkEqual(timer.displayText, "480m", "reset display")
}

private func testSubtractMinutesMarksTimeAsUsed() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.subtract(minutes: 30, now: now)

    checkEqual(timer.counted, 1800, accuracy: 0.001, "subtracted counted")
    checkEqual(timer.displayText, "450m", "subtracted display")
    check(!timer.isRunning, "subtracting must not start a paused timer")
}

private func testSubtractWhileRunningKeepsRunning() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.setRunning(true, now: now)
    timer.subtract(minutes: 5, now: now)
    check(timer.isRunning, "subtracting should not pause a running timer")

    timer.tick(now: now.addingTimeInterval(1), calendar: calendar)
    checkEqual(timer.counted, 301, accuracy: 0.001, "counted after subtraction")
}

private func testSubtractingMoreThanRemainingFinishesAndStops() {
    let now = date(2026, 1, 15, 9, 0)
    let almostDone = snapshot(counted: 28799, running: true, on: now)
    var timer = DailyTimer(snapshot: almostDone, now: now, calendar: calendar)

    timer.subtract(minutes: 5, now: now)

    checkEqual(timer.counted, 28800, accuracy: 0.001, "clamped subtracted counted")
    checkEqual(timer.displayText, "0m", "clamped subtracted display")
    check(timer.isFinished, "subtracting past the budget should finish the day")
    check(!timer.isRunning, "finished timer should stop after subtracting")
}

private func testNonPositiveSubtractIsIgnored() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.subtract(minutes: 0, now: now)
    timer.subtract(minutes: -25, now: now)

    checkEqual(timer.counted, 0, accuracy: 0.001, "ignored subtraction")
    checkEqual(timer.displayText, "480m", "ignored subtraction display")
}

private func testMidnightRolloverRefillsAndPauses() {
    let dayOne = date(2026, 1, 15, 23, 0)
    let saved = snapshot(counted: 120, running: true, on: dayOne)
    var timer = DailyTimer(snapshot: saved, now: dayOne, calendar: calendar)
    check(timer.isRunning, "restored timer should be running")

    timer.tick(now: date(2026, 1, 16, 0, 0, 1), calendar: calendar)

    checkEqual(timer.counted, 0, accuracy: 0.001, "rollover counted")
    check(!timer.isRunning, "rollover timer should be paused")
    checkEqual(timer.dayKey, "2026-01-16", "rollover day key")
    checkEqual(timer.displayText, "480m", "rollover display")
}

private func testMinutesRoundUpAndCollapseAtZero() {
    checkEqual(DailyTimer.minutes(from: 28800), 480, "28800s")
    checkEqual(DailyTimer.minutes(from: 28799), 480, "28799s")
    checkEqual(DailyTimer.minutes(from: 28740), 479, "28740s")
    checkEqual(DailyTimer.minutes(from: 60), 1, "60s")
    checkEqual(DailyTimer.minutes(from: 59), 1, "59s")
    checkEqual(DailyTimer.minutes(from: 1), 1, "1s")
    checkEqual(DailyTimer.minutes(from: 0), 0, "0s")
    checkEqual(DailyTimer.minutes(from: -10), 0, "negative")
}

private func testDisplayTextUsesMinutesOnly() {
    let now = date(2026, 1, 15, 9, 0)
    let saved = snapshot(counted: 60, running: false, on: now)
    let timer = DailyTimer(snapshot: saved, now: now, calendar: calendar)

    checkEqual(timer.displayText, "479m", "minute-only display")
}

private func testStoreRoundTrip() {
    let suiteName = "StudyTimerCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsTimerStore(defaults: defaults, key: "snapshot")
    check(store.load() == nil, "empty store should load nil")

    let saved = TimerSnapshot(dayKey: "2026-01-15", counted: 123.5, isRunning: true)
    store.save(saved)

    checkEqual(store.load(), saved, "store round trip")
}

// MARK: - Runner

testFreshDayStartsFullAndPaused()
testSnapshotFromAnotherDayIsDiscarded()
testPausedTimerDoesNotCount()
testResumedTimerCountsElapsedTime()
testPauseFreezesCountedTime()
testLongGapIsClampedInsteadOfConsumingTheBudget()
testSynchronizeAnchorsClockWithoutCountingGap()
testTimerStopsAtZeroAndCannotResume()
testManualResetRefillsAndPauses()
testSubtractMinutesMarksTimeAsUsed()
testSubtractWhileRunningKeepsRunning()
testSubtractingMoreThanRemainingFinishesAndStops()
testNonPositiveSubtractIsIgnored()
testMidnightRolloverRefillsAndPauses()
testMinutesRoundUpAndCollapseAtZero()
testDisplayTextUsesMinutesOnly()
testStoreRoundTrip()

if failures == 0 {
    print("All \(checks) checks passed.")
    exit(0)
} else {
    print("\(failures) of \(checks) checks failed.")
    exit(1)
}
