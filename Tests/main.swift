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

/// Builds a snapshot for `day` that is one second away from reaching zero and
/// carries the statistics from an earlier snapshot.
private func zeroCrossingSnapshot(on day: Date, carrying from: TimerSnapshot) -> TimerSnapshot {
    TimerSnapshot(dayKey: DailyTimer.dayKey(for: day, calendar: calendar),
                  counted: 28799,
                  spent: 28799,
                  isRunning: true,
                  timesReachedZero: from.timesReachedZero,
                  currentStreak: from.currentStreak,
                  longestStreak: from.longestStreak,
                  lastZeroDayKey: from.lastZeroDayKey)
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

private func testAddMinutesIncreasesRemainingWithoutSpending() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.add(minutes: 30, now: now)

    checkEqual(timer.counted, -1800, accuracy: 0.001, "added counted")
    checkEqual(timer.remaining, 30600, accuracy: 0.001, "added remaining")
    checkEqual(timer.displayText, "510m", "added display")
    checkEqual(timer.spentMinutes, 0, "adding must not spend time")
    check(!timer.isRunning, "adding must not start a paused timer")
}

private func testAddMinutesDoesNotChangeSpentTime() {
    let now = date(2026, 1, 15, 9, 0)
    let key = DailyTimer.dayKey(for: now, calendar: calendar)
    let saved = TimerSnapshot(dayKey: key, counted: 600,
                              spent: 600, isRunning: true)
    var timer = DailyTimer(snapshot: saved, now: now, calendar: calendar)

    timer.add(minutes: 20, now: now)

    checkEqual(timer.counted, -600, accuracy: 0.001, "counted after add")
    checkEqual(timer.spent, 600, accuracy: 0.001, "spent after add")
    checkEqual(timer.spentMinutes, 10, "spent minutes after add")
    checkEqual(timer.remaining, 29400, accuracy: 0.001, "remaining after add")
    check(timer.isRunning, "adding should not pause a running timer")

    timer.tick(now: now.addingTimeInterval(1), calendar: calendar)
    checkEqual(timer.counted, -599, accuracy: 0.001, "counted after add tick")
    checkEqual(timer.spent, 601, accuracy: 0.001, "spent after add tick")
}

private func testAddAndSubtractKeepSpentIndependent() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.add(minutes: 60, now: now)
    timer.subtract(minutes: 30, now: now)

    checkEqual(timer.counted, -1800, accuracy: 0.001, "net counted")
    checkEqual(timer.displayText, "510m", "net display")
    checkEqual(timer.spentMinutes, 30, "net spent minutes")
}

private func testNonPositiveAddIsIgnored() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.add(minutes: 0, now: now)
    timer.add(minutes: -25, now: now)

    checkEqual(timer.counted, 0, accuracy: 0.001, "ignored addition")
    checkEqual(timer.displayText, "480m", "ignored addition display")
    checkEqual(timer.spentMinutes, 0, "ignored addition spent")
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

private func testVersionedSnapshotPreservesIndependentSpent() {
    let original = TimerSnapshot(dayKey: "2026-01-15", counted: -1800,
                                 spent: 600, isRunning: true)
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(TimerSnapshot.self, from: data)

    checkEqual(decoded.counted, -1800, accuracy: 0.001, "versioned counted")
    checkEqual(decoded.spent, 600, accuracy: 0.001, "versioned spent")
    check(decoded.isRunning, "versioned running flag")
}

private func testReachingZeroRecordsCountAndStartsStreak() {
    let now = date(2026, 1, 15, 9, 0)
    let almostDone = snapshot(counted: 28799, running: true, on: now)
    var timer = DailyTimer(snapshot: almostDone, now: now, calendar: calendar)

    timer.tick(now: now.addingTimeInterval(1), calendar: calendar)

    checkEqual(timer.timesReachedZero, 1, "zero count after crossing")
    checkEqual(timer.currentStreak, 1, "current streak after first zero")
    checkEqual(timer.longestStreak, 1, "longest streak after first zero")
    checkEqual(timer.snapshot().lastZeroDayKey, "2026-01-15", "last zero day")
}

private func testRepeatedZeroSameDayDoesNotExtendStreak() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    timer.subtract(minutes: 480, now: now, calendar: calendar)
    checkEqual(timer.timesReachedZero, 1, "first zero count")
    checkEqual(timer.currentStreak, 1, "first zero streak")

    timer.add(minutes: 60, now: now)
    timer.subtract(minutes: 60, now: now, calendar: calendar)

    checkEqual(timer.timesReachedZero, 2, "second zero count")
    checkEqual(timer.currentStreak, 1, "same-day zero does not extend streak")
    checkEqual(timer.longestStreak, 1, "same-day zero does not extend longest")
}

private func testConsecutiveDaysExtendStreak() {
    let day1 = date(2026, 1, 15, 9, 0)
    var first = DailyTimer(snapshot: snapshot(counted: 28799, running: true, on: day1),
                           now: day1, calendar: calendar)
    first.tick(now: day1.addingTimeInterval(1), calendar: calendar)
    checkEqual(first.currentStreak, 1, "day 1 streak")

    let day2 = date(2026, 1, 16, 9, 0)
    var second = DailyTimer(snapshot: zeroCrossingSnapshot(on: day2, carrying: first.snapshot()),
                            now: day2, calendar: calendar)
    second.tick(now: day2.addingTimeInterval(1), calendar: calendar)

    checkEqual(second.timesReachedZero, 2, "zero count across two days")
    checkEqual(second.currentStreak, 2, "consecutive-day streak")
    checkEqual(second.longestStreak, 2, "longest consecutive streak")
}

private func testSkippedDayResetsCurrentStreakButKeepsLongest() {
    let day1 = date(2026, 1, 15, 9, 0)
    var first = DailyTimer(snapshot: snapshot(counted: 28799, running: true, on: day1),
                           now: day1, calendar: calendar)
    first.tick(now: day1.addingTimeInterval(1), calendar: calendar)

    let day2 = date(2026, 1, 16, 9, 0)
    var second = DailyTimer(snapshot: zeroCrossingSnapshot(on: day2, carrying: first.snapshot()),
                            now: day2, calendar: calendar)
    second.tick(now: day2.addingTimeInterval(1), calendar: calendar)
    checkEqual(second.longestStreak, 2, "two-day longest before skip")

    let day4 = date(2026, 1, 18, 9, 0)
    var fourth = DailyTimer(snapshot: zeroCrossingSnapshot(on: day4, carrying: second.snapshot()),
                            now: day4, calendar: calendar)
    checkEqual(fourth.currentStreak, 0, "skipped day clears current streak")
    checkEqual(fourth.longestStreak, 2, "skipped day keeps longest streak")

    fourth.tick(now: day4.addingTimeInterval(1), calendar: calendar)
    checkEqual(fourth.currentStreak, 1, "new streak after skipped day")
    checkEqual(fourth.longestStreak, 2, "new streak cannot beat longest")
    checkEqual(fourth.timesReachedZero, 3, "zero count keeps accumulating")
}

private func testSnapshotRoundTripPreservesStatistics() {
    let original = TimerSnapshot(dayKey: "2026-01-15",
                                 counted: 120,
                                 spent: 120,
                                 isRunning: false,
                                 timesReachedZero: 7,
                                 currentStreak: 3,
                                 longestStreak: 5,
                                 lastZeroDayKey: "2026-01-15")
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(TimerSnapshot.self, from: data)

    checkEqual(decoded.timesReachedZero, 7, "round trip zero count")
    checkEqual(decoded.currentStreak, 3, "round trip current streak")
    checkEqual(decoded.longestStreak, 5, "round trip longest streak")
    checkEqual(decoded.lastZeroDayKey, "2026-01-15", "round trip last zero day")
}

private func testOlderSnapshotsDefaultStatisticsToZero() {
    let json = """
    {"version":3,"dayKey":"2026-01-15","counted":120,"spent":120,"isRunning":false}
    """.data(using: .utf8)!

    let decoded = try! JSONDecoder().decode(TimerSnapshot.self, from: json)

    checkEqual(decoded.timesReachedZero, 0, "migrated zero count")
    checkEqual(decoded.currentStreak, 0, "migrated current streak")
    checkEqual(decoded.longestStreak, 0, "migrated longest streak")
    check(decoded.lastZeroDayKey == nil, "migrated last zero day")
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

    let saved = TimerSnapshot(dayKey: "2026-01-15", counted: 30000, isRunning: true,
                              timesReachedZero: 2, currentStreak: 2,
                              longestStreak: 2, lastZeroDayKey: "2026-01-15")
    store.save(saved)

    checkEqual(store.load(), saved, "store round trip")
}

private func testTaskAddTrimsAndRejectsBlankTitles() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)

    let added = list.add(title: "  Read chapter  ", now: now)

    checkEqual(added?.title ?? "", "Read chapter", "trimmed task title")
    check(list.add(title: "   ", now: now) == nil, "blank task rejected")
    checkEqual(list.tasks.count, 1, "blank task not stored")
}

private func testTaskDeleteRemovesOnlyThatTask() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let first = list.add(title: "First", now: now)!
    let second = list.add(title: "Second", now: now)!

    list.delete(id: first.id, now: now)

    checkEqual(list.tasks.count, 1, "one task after delete")
    checkEqual(list.tasks.first?.id, second.id, "delete keeps other tasks")
}

private func testCompletingTaskKeepsItInTheList() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let task = list.add(title: "Read", now: now)!

    list.setCompleted(true, id: task.id, now: now)

    checkEqual(list.tasks.count, 1, "completed task is kept")
    check(list.tasks[0].isCompleted, "task marked completed")

    list.toggleCompleted(id: task.id, now: now)
    check(!list.tasks[0].isCompleted, "task can be reopened")
    checkEqual(list.tasks.count, 1, "reopening does not delete")
}

private func testCompletingRunningTaskStopsItsClock() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let task = list.add(title: "Read", now: now)!

    list.start(id: task.id, now: now)
    list.tick(now: now.addingTimeInterval(1), isActive: true)
    list.setCompleted(true, id: task.id, now: now.addingTimeInterval(1))
    list.tick(now: now.addingTimeInterval(61), isActive: true)

    check(!list.tasks[0].isRunning, "completing stops the task clock")
    checkEqual(list.tasks[0].elapsed, 1, accuracy: 0.001,
               "elapsed freezes when completed")
    check(list.tasks[0].isCompleted, "task stays completed")
}

private func testClearCompletedRemovesOnlyCompletedTasks() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let done = list.add(title: "Done", now: now)!
    let open = list.add(title: "Open", now: now)!
    list.setCompleted(true, id: done.id, now: now)

    check(list.hasCompletedTasks, "list reports completed tasks")
    list.clearCompleted(now: now)

    checkEqual(list.tasks.count, 1, "clear keeps open tasks")
    checkEqual(list.tasks.first?.id, open.id, "open task survives clear")
    check(!list.hasCompletedTasks, "no completed tasks remain")
}

private func testDeleteAllRemovesEveryTask() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let done = list.add(title: "Done", now: now)!
    let running = list.add(title: "Running", now: now)!
    list.setCompleted(true, id: done.id, now: now)
    list.start(id: running.id, now: now)
    list.tick(now: now.addingTimeInterval(1), isActive: true)

    list.deleteAll(now: now.addingTimeInterval(1))

    check(list.tasks.isEmpty, "delete all removes every task")
    check(list.runningTask == nil, "delete all clears the running task")
    check(!list.hasCompletedTasks, "delete all leaves no completed tasks")
}

private func testTaskStartAndStopTrackElapsedTime() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let task = list.add(title: "Read", now: now)!

    list.start(id: task.id, now: now)
    check(list.tasks[0].isRunning, "task starts running")

    list.tick(now: now.addingTimeInterval(1), isActive: true)
    checkEqual(list.tasks[0].elapsed, 1, accuracy: 0.001, "elapsed after one second")

    list.tick(now: now.addingTimeInterval(61), isActive: true)
    checkEqual(list.tasks[0].elapsed, 3, accuracy: 0.001, "elapsed clamps long gaps")

    for second in 0..<60 {
        list.tick(now: now.addingTimeInterval(61 + Double(second)),
                  isActive: true)
    }
    checkEqual(list.tasks[0].elapsedMinutes, 1, "elapsed minutes round down")

    list.stop(id: task.id, now: now.addingTimeInterval(120))
    list.tick(now: now.addingTimeInterval(300), isActive: true)
    checkEqual(list.tasks[0].elapsed, 62, accuracy: 0.001,
               "stopped task does not accrue")
}

private func testStartingAnotherTaskStopsTheFirst() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let first = list.add(title: "First", now: now)!
    let second = list.add(title: "Second", now: now)!

    list.start(id: first.id, now: now)
    list.tick(now: now.addingTimeInterval(1), isActive: true)
    list.start(id: second.id, now: now.addingTimeInterval(1))
    list.tick(now: now.addingTimeInterval(2), isActive: true)

    check(!list.tasks[0].isRunning, "first task stopped")
    check(list.tasks[1].isRunning, "second task running")
    checkEqual(list.tasks[0].elapsed, 1, accuracy: 0.001, "first elapsed frozen")
    checkEqual(list.tasks[1].elapsed, 1, accuracy: 0.001, "second elapsed counted")
    checkEqual(list.runningTask?.id, second.id, "only one running task")
}

private func testTaskClockFollowsStudyTimerState() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let task = list.add(title: "Read", now: now)!

    list.start(id: task.id, now: now)
    list.tick(now: now.addingTimeInterval(60), isActive: false)
    checkEqual(list.tasks[0].elapsed, 0, accuracy: 0.001,
               "paused study timer freezes task time")
    check(list.tasks[0].isRunning, "task stays selected while paused")

    list.tick(now: now.addingTimeInterval(61), isActive: true)
    checkEqual(list.tasks[0].elapsed, 1, accuracy: 0.001,
               "task resumes with the study timer")
}

private func testCompletedTaskCannotBeStarted() {
    let now = date(2026, 1, 15, 9, 0)
    var list = TaskList(snapshot: nil, now: now)
    let task = list.add(title: "Read", now: now)!
    list.setCompleted(true, id: task.id, now: now)

    list.start(id: task.id, now: now)

    check(!list.tasks[0].isRunning, "completed task cannot start")
}

private func testTaskListLoadStopsRunningTasks() {
    let now = date(2026, 1, 15, 9, 0)
    let saved = TaskSnapshot(tasks: [
        StudyTask(title: "Running", elapsed: 120, isRunning: true),
        StudyTask(title: "Done", isCompleted: true, elapsed: 300),
    ])

    let list = TaskList(snapshot: saved, now: now)

    check(!list.tasks[0].isRunning, "loaded task is paused on quit")
    checkEqual(list.tasks[0].elapsed, 120, accuracy: 0.001,
               "loaded elapsed is preserved")
    check(list.tasks[1].isCompleted, "completed state is preserved")
}

private func testTaskStoreRoundTrip() {
    let suiteName = "StudyTaskCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsTaskStore(defaults: defaults, key: "tasks")
    check(store.load() == nil, "empty task store should load nil")

    let saved = TaskSnapshot(tasks: [
        StudyTask(title: "Read", elapsed: 125),
        StudyTask(title: "Write", isCompleted: true, elapsed: 60),
    ])
    store.save(saved)

    checkEqual(store.load(), saved, "task store round trip")
}

private func testTaskSnapshotSurvivesJSONRoundTrip() {
    let original = TaskSnapshot(tasks: [
        StudyTask(title: "Read", isCompleted: true, elapsed: 125),
    ])
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(TaskSnapshot.self, from: data)

    checkEqual(decoded, original, "task snapshot JSON round trip")
}

private func testChangingBudgetRecomputesRemaining() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)

    checkEqual(timer.budgetMinutes, 480, "default budget minutes")
    checkEqual(timer.displayText, "480m", "default display")

    timer.setBudget(minutes: 60, now: now)
    checkEqual(timer.budgetMinutes, 60, "smaller budget minutes")
    checkEqual(timer.displayText, "60m", "smaller budget display")

    timer.subtract(minutes: 10, now: now, calendar: calendar)
    checkEqual(timer.displayText, "50m", "remaining after subtract")

    timer.setBudget(minutes: 120, now: now)
    checkEqual(timer.displayText, "110m", "remaining after raising budget")
    checkEqual(timer.spentMinutes, 10, "budget change leaves spent alone")
}

private func testBudgetPersistsInSnapshot() {
    let now = date(2026, 1, 15, 9, 0)
    var timer = DailyTimer(snapshot: nil, now: now, calendar: calendar)
    timer.setBudget(minutes: 90, now: now)

    let data = try! JSONEncoder().encode(timer.snapshot())
    let decoded = try! JSONDecoder().decode(TimerSnapshot.self, from: data)
    let restored = DailyTimer(snapshot: decoded, now: now, calendar: calendar)

    checkEqual(decoded.budget, 5400, accuracy: 0.001, "snapshot budget")
    checkEqual(restored.budgetMinutes, 90, "restored budget minutes")
    checkEqual(restored.displayText, "90m", "restored display")
}

private func testLegacySnapshotWithoutBudgetUsesDefault() {
    let json = """
    {"dayKey":"2026-01-15","version":4,"counted":600,"spent":600,"isRunning":false}
    """.data(using: .utf8)!

    let decoded = try! JSONDecoder().decode(TimerSnapshot.self, from: json)
    let timer = DailyTimer(snapshot: decoded, now: date(2026, 1, 15, 9, 0),
                           calendar: calendar)

    checkEqual(timer.budgetMinutes, 480, "legacy budget defaults to 480")
    checkEqual(timer.displayText, "470m", "legacy display uses default budget")
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
testAddMinutesIncreasesRemainingWithoutSpending()
testAddMinutesDoesNotChangeSpentTime()
testAddAndSubtractKeepSpentIndependent()
testNonPositiveAddIsIgnored()
testNonPositiveSubtractIsIgnored()
testMidnightRolloverRefillsAndPauses()
testSpentMinutesRoundDown()
testLegacySnapshotWithoutSpentKeyStillLoads()
testSnapshotWithOldSpentFieldShowsCountedMinutes()
testVersionedSnapshotPreservesIndependentSpent()
testReachingZeroRecordsCountAndStartsStreak()
testRepeatedZeroSameDayDoesNotExtendStreak()
testConsecutiveDaysExtendStreak()
testSkippedDayResetsCurrentStreakButKeepsLongest()
testSnapshotRoundTripPreservesStatistics()
testOlderSnapshotsDefaultStatisticsToZero()
testMinutesRoundUpAndCollapseAtZero()
testDisplayTextUsesMinutesOnly()
testStoreRoundTrip()
testTaskAddTrimsAndRejectsBlankTitles()
testTaskDeleteRemovesOnlyThatTask()
testCompletingTaskKeepsItInTheList()
testCompletingRunningTaskStopsItsClock()
testClearCompletedRemovesOnlyCompletedTasks()
testDeleteAllRemovesEveryTask()
testTaskStartAndStopTrackElapsedTime()
testStartingAnotherTaskStopsTheFirst()
testTaskClockFollowsStudyTimerState()
testCompletedTaskCannotBeStarted()
testTaskListLoadStopsRunningTasks()
testTaskStoreRoundTrip()
testTaskSnapshotSurvivesJSONRoundTrip()
testChangingBudgetRecomputesRemaining()
testBudgetPersistsInSnapshot()
testLegacySnapshotWithoutBudgetUsesDefault()

if failures == 0 {
    print("All \(checks) checks passed.")
    exit(0)
} else {
    print("\(failures) of \(checks) checks failed.")
    exit(1)
}
