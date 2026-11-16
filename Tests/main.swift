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
    check(!timer.isOverBudget, "fresh timer should not be over budget")
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

private func testRunningPastBudgetGoesNegative() {
    let now = date(2026, 1, 15, 9, 0)
    let almostDone = snapshot(counted: 28799, running: true, on: now)
    var timer = DailyTimer(snapshot: almostDone, now: now, calendar: calendar)

    check(timer.isRunning, "restored timer should be running")

    for second in 1...61 {
        timer.tick(now: now.addingTimeInterval(Double(second)), calendar: calendar)
    }

    checkEqual(timer.counted, 28860, accuracy: 0.001, "overrun counted")
    check(timer.isOverBudget, "timer should be over budget")
    check(timer.isRunning, "timer must keep running past zero")
    checkEqual(timer.displayText, "-1m", "negative display after a full minute")
    checkEqual(timer.minutesRemaining, -1, "negative minutes remaining")
    checkEqual(timer.spentMinutes, 481, "spent minutes past 480")
}

private func testFirstOverrunMinuteStillShowsZero() {
    let now = date(2026, 1, 15, 9, 0)
    let almostDone = snapshot(counted: 28799, running: true, on: now)
    var timer = DailyTimer(snapshot: almostDone, now: now, calendar: calendar)

    for second in 1...60 {
        timer.tick(now: now.addingTimeInterval(Double(second)), calendar: calendar)
    }

    check(timer.remaining < 0, "timer should already be over budget")
    checkEqual(timer.displayText, "0m", "less than a minute over")
    checkEqual(timer.minutesRemaining, 0, "truncated negative minutes")

    timer.tick(now: now.addingTimeInterval(61), calendar: calendar)
    checkEqual(timer.displayText, "-1m", "first full minute over")
    checkEqual(timer.minutesRemaining, -1, "negative minutes after a full minute")
}

private func testPausedOverrunCanResume() {
    let now = date(2026, 1, 15, 9, 0)
    let overrun = snapshot(counted: 29000, running: false, on: now)
    var timer = DailyTimer(snapshot: overrun, now: now, calendar: calendar)

    check(!timer.isRunning, "restored overrun timer should be paused")
    checkEqual(timer.counted, 29000, accuracy: 0.001, "overrun restored without clamping")
    checkEqual(timer.displayText, "-3m", "paused overrun display")

    timer.setRunning(true, now: now)
    check(timer.isRunning, "overrun timer should resume")

    timer.tick(now: now.addingTimeInterval(1), calendar: calendar)
    checkEqual(timer.counted, 29001, accuracy: 0.001, "overrun counts after resume")
}

private func testManualResetRefillsAndPauses() {
    let now = date(2026, 1, 15, 9, 0)
    let saved = snapshot(counted: 100, running: true, on: now)
    var timer = DailyTimer(snapshot: saved, now: now, calendar: calendar)

    timer.reset(now: now.addingTimeInterval(5), calendar: calendar)

    checkEqual(timer.counted, 0, accuracy: 0.001, "reset counted")
    checkEqual(timer.spentMinutes, 0, "reset spent minutes")
    check(!timer.isRunning, "reset timer should be paused")
    checkEqual(timer.displayText, "480m", "reset display")
}

private func testSpentTracksBudgetUsed() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    checkEqual(timer.spentMinutes, 0, "initial spent minutes")

    timer.setRunning(true, now: now)
    for second in 1...61 {
        timer.tick(now: now.addingTimeInterval(Double(second)), calendar: calendar)
    }

    checkEqual(timer.spentMinutes, 1, "spent minutes round down")

    timer.setRunning(false, now: now.addingTimeInterval(61))
    timer.tick(now: now.addingTimeInterval(121), calendar: calendar)
    checkEqual(timer.spentMinutes, 1, "spent frozen while paused")
}

private func testSubtractMinutesCountsAsSpent() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.subtract(minutes: 230, now: now)

    checkEqual(timer.counted, 13800, accuracy: 0.001, "subtracted counted")
    checkEqual(timer.displayText, "250m", "subtracted display")
    checkEqual(timer.spentMinutes, 230, "subtracted spent minutes")
    check(!timer.isRunning, "subtracting must not start a paused timer")
}

private func testSubtractIncreasesSpentTime() {
    let now = date(2026, 1, 15, 9, 0)
    let saved = snapshot(counted: 600, running: true, on: now)
    var timer = DailyTimer(snapshot: saved, now: now, calendar: calendar)

    timer.subtract(minutes: 20, now: now)

    checkEqual(timer.counted, 1800, accuracy: 0.001, "counted after subtract")
    checkEqual(timer.spentMinutes, 30, "spent minutes after subtract")
    check(timer.isRunning, "subtracting should not pause a running timer")

    timer.tick(now: now.addingTimeInterval(1), calendar: calendar)
    checkEqual(timer.spentMinutes, 30, "spent keeps counting after subtract")
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

private func testSubtractingPastZeroGoesNegative() {
    let now = date(2026, 1, 15, 9, 0)
    let fullDay = snapshot(counted: 28800, running: false, on: now)
    var timer = DailyTimer(snapshot: fullDay, now: now, calendar: calendar)

    timer.subtract(minutes: 5, now: now)

    checkEqual(timer.counted, 29100, accuracy: 0.001, "overrun subtracted counted")
    checkEqual(timer.remaining, -300, accuracy: 0.001, "overrun remaining")
    checkEqual(timer.displayText, "-5m", "overrun subtracted display")
    checkEqual(timer.spentMinutes, 485, "overrun spent minutes")
    check(!timer.isRunning, "subtracting must not start a paused timer")

    timer.setRunning(true, now: now)
    check(timer.isRunning, "subtraction overrun can be resumed")
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
    let saved = snapshot(counted: 30000, running: true, on: dayOne)
    var timer = DailyTimer(snapshot: saved, now: dayOne, calendar: calendar)
    check(timer.isRunning, "restored timer should be running")
    check(timer.isOverBudget, "restored timer should be over budget")

    timer.tick(now: date(2026, 1, 16, 0, 0, 1), calendar: calendar)

    checkEqual(timer.counted, 0, accuracy: 0.001, "rollover counted")
    checkEqual(timer.spentMinutes, 0, "rollover spent minutes")
    check(!timer.isRunning, "rollover timer should be paused")
    checkEqual(timer.dayKey, "2026-01-16", "rollover day key")
    checkEqual(timer.displayText, "480m", "rollover display")
}

private func testSpentMinutesRoundDown() {
    let now = date(2026, 1, 15, 9, 0)
    let dayKey = DailyTimer.dayKey(for: now, calendar: calendar)
    let cases: [(TimeInterval, Int)] = [
        (0, 0), (59, 0), (60, 1), (61, 1), (13800, 230),
        (28800, 480), (28860, 481), (29040, 484), (30000, 500)
    ]

    for (seconds, expected) in cases {
        let saved = TimerSnapshot(dayKey: dayKey, counted: seconds, isRunning: false)
        let timer = DailyTimer(snapshot: saved, now: now, calendar: calendar)
        checkEqual(timer.spentMinutes, expected, "spent minutes for \(seconds)s")
    }
}

private func testLegacySnapshotWithoutSpentKeyStillLoads() {
    let json = """
    {"dayKey":"2026-01-15","counted":120,"isRunning":false}
    """.data(using: .utf8)!

    let decoded = try! JSONDecoder().decode(TimerSnapshot.self, from: json)

    checkEqual(decoded.counted, 120, accuracy: 0.001, "legacy counted")
    check(!decoded.isRunning, "legacy running flag")
    checkEqual(DailyTimer(snapshot: decoded, now: date(2026, 1, 15, 9, 0),
                          calendar: calendar).spentMinutes,
               2, "legacy spent minutes")
}

private func testSnapshotWithOldSpentFieldShowsCountedMinutes() {
    let json = """
    {"dayKey":"2026-01-15","version":2,"counted":13800,"spent":0,"isRunning":false}
    """.data(using: .utf8)!

    let decoded = try! JSONDecoder().decode(TimerSnapshot.self, from: json)
    let timer = DailyTimer(snapshot: decoded, now: date(2026, 1, 15, 9, 0),
                           calendar: calendar)

    checkEqual(timer.counted, 13800, accuracy: 0.001, "old snapshot counted")
    checkEqual(timer.spentMinutes, 230, "old snapshot spent minutes")
}

private func testMinutesRoundUpAndCollapseAtZero() {
    checkEqual(DailyTimer.minutes(from: 28800), 480, "28800s")
    checkEqual(DailyTimer.minutes(from: 28799), 480, "28799s")
    checkEqual(DailyTimer.minutes(from: 28740), 479, "28740s")
    checkEqual(DailyTimer.minutes(from: 60), 1, "60s")
    checkEqual(DailyTimer.minutes(from: 59), 1, "59s")
    checkEqual(DailyTimer.minutes(from: 1), 1, "1s")
    checkEqual(DailyTimer.minutes(from: 0), 0, "0s")
    checkEqual(DailyTimer.minutes(from: -1), 0, "-1s")
    checkEqual(DailyTimer.minutes(from: -10), 0, "-10s")
    checkEqual(DailyTimer.minutes(from: -59), 0, "-59s")
    checkEqual(DailyTimer.minutes(from: -60), -1, "-60s")
    checkEqual(DailyTimer.minutes(from: -61), -1, "-61s")
    checkEqual(DailyTimer.minutes(from: -119), -1, "-119s")
    checkEqual(DailyTimer.minutes(from: -120), -2, "-120s")
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

    let saved = TimerSnapshot(dayKey: "2026-01-15", counted: 30000, isRunning: true)
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
testRunningPastBudgetGoesNegative()
testFirstOverrunMinuteStillShowsZero()
testPausedOverrunCanResume()
testManualResetRefillsAndPauses()
testSpentTracksBudgetUsed()
testSubtractMinutesCountsAsSpent()
testSubtractIncreasesSpentTime()
testSubtractWhileRunningKeepsRunning()
testSubtractingPastZeroGoesNegative()
testNonPositiveSubtractIsIgnored()
testMidnightRolloverRefillsAndPauses()
testSpentMinutesRoundDown()
testLegacySnapshotWithoutSpentKeyStillLoads()
testSnapshotWithOldSpentFieldShowsCountedMinutes()
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
