import Foundation

/// A snapshot of the timer that can be persisted between launches.
public struct TimerSnapshot: Codable, Equatable {
    /// Local calendar day the snapshot belongs to, formatted as `yyyy-MM-dd`.
    public var dayKey: String
    /// Seconds counted against the daily budget, including manual subtractions
    /// and credits from manual additions. May be negative after additions.
    public var counted: TimeInterval
    /// Seconds recorded as spent: running time plus manual subtractions.
    /// Additions never change this value.
    public var spent: TimeInterval
    /// Seconds spent studying across every day this app has tracked.
    public var lifetimeSpent: TimeInterval
    /// The daily budget in seconds that `counted` is measured against.
    public var budget: TimeInterval
    /// Minutes after local midnight when the study day rolls over.
    public var resetMinutes: Int
    /// Whether the timer was counting down when the snapshot was taken.
    public var isRunning: Bool

    /// Total number of times the countdown has crossed zero.
    public var timesReachedZero: Int
    /// Consecutive days on which zero has been reached.
    public var currentStreak: Int
    /// Longest consecutive-day streak ever recorded.
    public var longestStreak: Int
    /// Most recent day on which zero was reached, formatted `yyyy-MM-dd`.
    public var lastZeroDayKey: String?
    /// Completed days before today that recorded any study time.
    public var daysStudied: Int

    public init(dayKey: String,
                counted: TimeInterval,
                spent: TimeInterval? = nil,
                lifetimeSpent: TimeInterval? = nil,
                budget: TimeInterval = DailyTimer.dailyBudget,
                resetMinutes: Int = 0,
                isRunning: Bool,
                timesReachedZero: Int = 0,
                currentStreak: Int = 0,
                longestStreak: Int = 0,
                lastZeroDayKey: String? = nil,
                daysStudied: Int = 0) {
        self.dayKey = dayKey
        self.counted = counted
        let resolvedSpent = spent ?? max(0, counted)
        self.spent = resolvedSpent
        self.lifetimeSpent = max(0, lifetimeSpent ?? resolvedSpent)
        self.budget = budget
        self.resetMinutes = min(max(resetMinutes, 0), 1439)
        self.isRunning = isRunning
        self.timesReachedZero = timesReachedZero
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastZeroDayKey = lastZeroDayKey
        self.daysStudied = max(0, daysStudied)
    }

    private enum CodingKeys: String, CodingKey {
        case version, dayKey, counted, spent, lifetimeSpent, budget, resetMinutes, isRunning
        case timesReachedZero, currentStreak, longestStreak, lastZeroDayKey, daysStudied
    }

    /// Version 8 adds the configurable daily reset time.
    private static let currentSchemaVersion = 8

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        let decodedCounted = try container.decode(TimeInterval.self, forKey: .counted)
        let decodedSpent = try container.decodeIfPresent(TimeInterval.self, forKey: .spent)

        dayKey = try container.decode(String.self, forKey: .dayKey)
        counted = decodedCounted
        let resolvedSpent: TimeInterval
        if version >= 3 {
            resolvedSpent = max(0, decodedSpent ?? decodedCounted)
        } else {
            // Older formats did not support additions and counted subtractions
            // as spent, so counted is the best available value.
            resolvedSpent = max(0, decodedCounted)
        }
        spent = resolvedSpent
        lifetimeSpent = max(0, try container.decodeIfPresent(TimeInterval.self,
                                                             forKey: .lifetimeSpent)
                                ?? resolvedSpent)
        budget = max(60, try container.decodeIfPresent(TimeInterval.self,
                                                       forKey: .budget) ?? DailyTimer.dailyBudget)
        resetMinutes = min(max(try container.decodeIfPresent(Int.self,
                                                             forKey: .resetMinutes) ?? 0, 0), 1439)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        timesReachedZero = max(0, try container.decodeIfPresent(Int.self,
                                                               forKey: .timesReachedZero) ?? 0)
        currentStreak = max(0, try container.decodeIfPresent(Int.self,
                                                            forKey: .currentStreak) ?? 0)
        longestStreak = max(0, try container.decodeIfPresent(Int.self,
                                                            forKey: .longestStreak) ?? 0)
        lastZeroDayKey = try container.decodeIfPresent(String.self, forKey: .lastZeroDayKey)
        daysStudied = max(0, try container.decodeIfPresent(Int.self,
                                                           forKey: .daysStudied) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(TimerSnapshot.currentSchemaVersion, forKey: .version)
        try container.encode(dayKey, forKey: .dayKey)
        try container.encode(counted, forKey: .counted)
        try container.encode(spent, forKey: .spent)
        try container.encode(lifetimeSpent, forKey: .lifetimeSpent)
        try container.encode(budget, forKey: .budget)
        try container.encode(resetMinutes, forKey: .resetMinutes)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(timesReachedZero, forKey: .timesReachedZero)
        try container.encode(currentStreak, forKey: .currentStreak)
        try container.encode(longestStreak, forKey: .longestStreak)
        try container.encodeIfPresent(lastZeroDayKey, forKey: .lastZeroDayKey)
        try container.encode(daysStudied, forKey: .daysStudied)
    }
}

/// Tracks the 8-hour daily study budget.
///
/// Time only drains while the timer is running. The timer is allowed to run
/// past the daily budget, in which case the remaining time goes negative.
/// Day rollover happens at the configured reset time (midnight by default) and
/// always leaves the timer paused with a full budget.
public struct DailyTimer {
    /// Eight hours per day by default. A snapshot can carry a different budget
    /// after the user changes it in Settings.
    public static let dailyBudget: TimeInterval = 8 * 60 * 60

    /// Anything longer than this between ticks is treated as sleep or a gap and
    /// is not counted, so the budget tracks actual awake time at the machine.
    private static let maximumTickGap: TimeInterval = 2

    public private(set) var counted: TimeInterval
    /// Time recorded as spent: running time plus manual subtractions.
    public private(set) var spent: TimeInterval
    /// All-time time spent studying, accumulated across days.
    public private(set) var lifetimeSpent: TimeInterval
    /// Days before today that recorded study time.
    public private(set) var completedStudyDays: Int
    /// The budget in seconds that `counted` is measured against.
    public private(set) var budget: TimeInterval
    /// Minutes after local midnight when the study day rolls over.
    public private(set) var resetMinutes: Int
    public private(set) var isRunning: Bool
    public private(set) var dayKey: String
    /// Total number of times the countdown has crossed zero.
    public private(set) var timesReachedZero: Int
    /// Consecutive days on which zero has been reached.
    public private(set) var currentStreak: Int
    /// Longest consecutive-day streak ever recorded.
    public private(set) var longestStreak: Int
    private var lastZeroDayKey: String?
    private var lastTick: Date

    public init(snapshot: TimerSnapshot?,
                now: Date,
                calendar: Calendar = .current,
                resetMinutes: Int? = nil) {
        let effectiveReset = min(max(resetMinutes ?? snapshot?.resetMinutes ?? 0, 0), 1439)
        let key = DailyTimer.dayKey(for: now, calendar: calendar,
                                    resetMinutes: effectiveReset)
        self.dayKey = key
        self.lastTick = now
        self.budget = max(60, snapshot?.budget ?? DailyTimer.dailyBudget)
        self.resetMinutes = effectiveReset
        self.lifetimeSpent = max(snapshot?.lifetimeSpent ?? 0, 0)

        let restoredStudyDays = max(snapshot?.daysStudied ?? 0, 0)
        if let snapshot = snapshot, snapshot.dayKey != key, snapshot.spent > 0 {
            // The app was closed on a day that recorded study time, so count
            // that day before starting fresh.
            self.completedStudyDays = restoredStudyDays + 1
        } else {
            self.completedStudyDays = restoredStudyDays
        }

        let restoredCurrentStreak = max(snapshot?.currentStreak ?? 0, 0)
        self.timesReachedZero = max(snapshot?.timesReachedZero ?? 0, 0)
        self.currentStreak = restoredCurrentStreak
        self.longestStreak = max(snapshot?.longestStreak ?? 0, restoredCurrentStreak)
        self.lastZeroDayKey = snapshot?.lastZeroDayKey

        if let snapshot = snapshot, snapshot.dayKey == key {
            self.counted = snapshot.counted
            self.spent = max(snapshot.spent, 0)
            self.isRunning = snapshot.isRunning
        } else {
            // First launch of the day, or the saved state is from another day.
            // All-time statistics still carry over.
            self.counted = 0
            self.spent = 0
            self.isRunning = false
        }

        expireStreakIfNeeded(now: now, calendar: calendar)
    }

    /// Seconds left in today's budget. Negative once the timer has overrun.
    public var remaining: TimeInterval {
        budget - counted
    }

    /// The daily budget in whole minutes.
    public var budgetMinutes: Int {
        Int((max(60, budget) / 60).rounded())
    }

    public var isOverBudget: Bool {
        remaining < 0
    }

    /// Remaining time in whole minutes. Positive time rounds up; negative time
    /// truncates toward zero, so the first negative minute appears only after a
    /// full minute of overrun.
    public var minutesRemaining: Int {
        DailyTimer.minutes(from: remaining)
    }

    /// Compact text for the menu bar, e.g. `480m`, `0m`, or `-2m`.
    public var displayText: String {
        DailyTimer.minutesText(from: remaining)
    }

    /// Whole minutes recorded as spent, including manual subtractions but not
    /// manual additions, rounded down. Can exceed 480.
    public var spentMinutes: Int {
        Int(max(0, spent) / 60)
    }

    /// All-time spent time in whole minutes, rounded down.
    public var lifetimeSpentMinutes: Int {
        Int(max(0, lifetimeSpent) / 60)
    }

    /// Days with study time, including today when any time has been recorded.
    public var daysStudied: Int {
        completedStudyDays + (spent > 0 ? 1 : 0)
    }

    public static func minutes(from remaining: TimeInterval) -> Int {
        if remaining > 0 {
            return Int(ceil(remaining / 60))
        }
        if remaining < 0 {
            return Int(remaining / 60)
        }
        return 0
    }

    public static func minutesText(from remaining: TimeInterval) -> String {
        "\(minutes(from: remaining))m"
    }

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }

    /// The study-day key for `date`, shifted by the configured reset time. A
    /// reset at 1 AM keeps times between midnight and 1 AM on the previous day.
    public static func dayKey(for date: Date,
                              calendar: Calendar,
                              resetMinutes: Int) -> String {
        let clamped = min(max(resetMinutes, 0), 1439)
        let shifted = date.addingTimeInterval(-TimeInterval(clamped) * 60)
        return dayKey(for: shifted, calendar: calendar)
    }

    private func shiftedDate(for date: Date) -> Date {
        date.addingTimeInterval(-TimeInterval(resetMinutes) * 60)
    }

    private func studyDayKey(for date: Date, calendar: Calendar) -> String {
        DailyTimer.dayKey(for: shiftedDate(for: date), calendar: calendar)
    }

    /// Advances the timer to `now`, counting a small delta if it is running.
    public mutating func tick(now: Date, calendar: Calendar = .current) {
        if handleDayChange(now: now, calendar: calendar) {
            return
        }

        defer { lastTick = now }

        guard isRunning else { return }

        let delta = now.timeIntervalSince(lastTick)
        guard delta > 0 else { return }

        let gap = min(delta, DailyTimer.maximumTickGap)
        let wasAboveZero = remaining > 0
        counted += gap
        spent += gap
        lifetimeSpent += gap

        if wasAboveZero && remaining <= 0 {
            recordZeroReached(now: now, calendar: calendar)
        }
    }

    /// Starts a fresh day if `now` falls past the configured reset time on a
    /// different study day. Returns `true` when the timer was reset.
    @discardableResult
    public mutating func handleDayChange(now: Date, calendar: Calendar = .current) -> Bool {
        let key = studyDayKey(for: now, calendar: calendar)
        guard key != dayKey else { return false }

        dayKey = key
        if spent > 0 {
            completedStudyDays += 1
        }
        counted = 0
        spent = 0
        isRunning = false
        lastTick = now
        expireStreakIfNeeded(now: now, calendar: calendar)
        return true
    }

    /// Pauses or resumes. Resuming is allowed even when the budget is spent.
    public mutating func setRunning(_ running: Bool, now: Date) {
        isRunning = running
        lastTick = now
    }

    public mutating func toggle(now: Date) {
        setRunning(!isRunning, now: now)
    }

    /// Refills the budget for today and leaves the timer paused.
    public mutating func reset(now: Date, calendar: Calendar = .current) {
        counted = 0
        spent = 0
        isRunning = false
        dayKey = studyDayKey(for: now, calendar: calendar)
        lastTick = now
    }

    /// Changes the daily budget without touching time already counted. Lowering
    /// the budget can make the remaining time negative.
    public mutating func setBudget(minutes: Int, now: Date) {
        guard minutes > 0 else { return }
        budget = TimeInterval(minutes) * 60
        lastTick = now
    }

    /// Changes the reset time in minutes after midnight. Moving the boundary
    /// earlier than the current time starts a fresh day; moving it later keeps
    /// today's progress until the new boundary is reached.
    public mutating func setResetTime(minutes: Int,
                                      now: Date,
                                      calendar: Calendar = .current) {
        let normalized = ((minutes % 1440) + 1440) % 1440
        resetMinutes = normalized

        let key = studyDayKey(for: now, calendar: calendar)
        if key > dayKey {
            if spent > 0 {
                completedStudyDays += 1
            }
            dayKey = key
            counted = 0
            spent = 0
            isRunning = false
            lastTick = now
            expireStreakIfNeeded(now: now, calendar: calendar)
        } else if key < dayKey {
            dayKey = key
            lastTick = now
        }
    }

    /// Adds time back to today's remaining budget. Additions do not count as
    /// time spent and can raise the remaining time above the daily budget.
    public mutating func add(minutes: Int, now: Date) {
        guard minutes > 0 else { return }

        counted -= TimeInterval(minutes) * 60
        lastTick = now
    }

    /// Marks the given number of minutes as already used. This can push the
    /// remaining time below zero and never changes the running state.
    public mutating func subtract(minutes: Int,
                                  now: Date,
                                  calendar: Calendar = .current) {
        guard minutes > 0 else { return }

        let wasAboveZero = remaining > 0
        let amount = TimeInterval(minutes) * 60
        counted += amount
        spent += amount
        lifetimeSpent += amount
        lastTick = now

        if wasAboveZero && remaining <= 0 {
            recordZeroReached(now: now, calendar: calendar)
        }
    }

    /// Re-anchors the tick clock without counting the elapsed gap. Used after
    /// wake-from-sleep and day-change notifications.
    public mutating func synchronize(now: Date, calendar: Calendar = .current) {
        handleDayChange(now: now, calendar: calendar)
        lastTick = now
    }

    public func snapshot() -> TimerSnapshot {
        TimerSnapshot(dayKey: dayKey,
                      counted: counted,
                      spent: spent,
                      lifetimeSpent: lifetimeSpent,
                      budget: budget,
                      resetMinutes: resetMinutes,
                      isRunning: isRunning,
                      timesReachedZero: timesReachedZero,
                      currentStreak: currentStreak,
                      longestStreak: longestStreak,
                      lastZeroDayKey: lastZeroDayKey,
                      daysStudied: completedStudyDays)
    }

    // MARK: - Statistics

    private mutating func recordZeroReached(now: Date, calendar: Calendar) {
        timesReachedZero += 1

        let studyNow = shiftedDate(for: now)
        let today = DailyTimer.dayKey(for: studyNow, calendar: calendar)
        guard lastZeroDayKey != today else { return }

        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: studyNow) ?? studyNow
        let yesterday = DailyTimer.dayKey(for: yesterdayDate, calendar: calendar)

        if lastZeroDayKey == yesterday {
            currentStreak += 1
        } else {
            currentStreak = 1
        }
        lastZeroDayKey = today
        longestStreak = max(longestStreak, currentStreak)
    }

    /// A streak stays alive through the day after its last zero. If neither
    /// today nor yesterday recorded a zero, it is no longer current.
    private mutating func expireStreakIfNeeded(now: Date, calendar: Calendar) {
        guard currentStreak > 0 else { return }
        guard let lastZeroDayKey = lastZeroDayKey else {
            currentStreak = 0
            return
        }

        let studyNow = shiftedDate(for: now)
        let today = DailyTimer.dayKey(for: studyNow, calendar: calendar)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: studyNow) ?? studyNow
        let yesterday = DailyTimer.dayKey(for: yesterdayDate, calendar: calendar)

        if lastZeroDayKey != today && lastZeroDayKey != yesterday {
            currentStreak = 0
        }
    }
}
