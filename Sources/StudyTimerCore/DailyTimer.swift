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

    public init(dayKey: String,
                counted: TimeInterval,
                spent: TimeInterval? = nil,
                isRunning: Bool,
                timesReachedZero: Int = 0,
                currentStreak: Int = 0,
                longestStreak: Int = 0,
                lastZeroDayKey: String? = nil) {
        self.dayKey = dayKey
        self.counted = counted
        self.spent = spent ?? max(0, counted)
        self.isRunning = isRunning
        self.timesReachedZero = timesReachedZero
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastZeroDayKey = lastZeroDayKey
    }

    private enum CodingKeys: String, CodingKey {
        case version, dayKey, counted, spent, isRunning
        case timesReachedZero, currentStreak, longestStreak, lastZeroDayKey
    }

    /// Version 4 adds the zero-reached and streak statistics.
    private static let currentSchemaVersion = 4

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        let decodedCounted = try container.decode(TimeInterval.self, forKey: .counted)
        let decodedSpent = try container.decodeIfPresent(TimeInterval.self, forKey: .spent)

        dayKey = try container.decode(String.self, forKey: .dayKey)
        counted = decodedCounted
        if version >= 3 {
            spent = max(0, decodedSpent ?? decodedCounted)
        } else {
            // Older formats did not support additions and counted subtractions
            // as spent, so counted is the best available value.
            spent = max(0, decodedCounted)
        }
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        timesReachedZero = max(0, try container.decodeIfPresent(Int.self,
                                                               forKey: .timesReachedZero) ?? 0)
        currentStreak = max(0, try container.decodeIfPresent(Int.self,
                                                            forKey: .currentStreak) ?? 0)
        longestStreak = max(0, try container.decodeIfPresent(Int.self,
                                                            forKey: .longestStreak) ?? 0)
        lastZeroDayKey = try container.decodeIfPresent(String.self, forKey: .lastZeroDayKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(TimerSnapshot.currentSchemaVersion, forKey: .version)
        try container.encode(dayKey, forKey: .dayKey)
        try container.encode(counted, forKey: .counted)
        try container.encode(spent, forKey: .spent)
        try container.encode(isRunning, forKey: .isRunning)
        try container.encode(timesReachedZero, forKey: .timesReachedZero)
        try container.encode(currentStreak, forKey: .currentStreak)
        try container.encode(longestStreak, forKey: .longestStreak)
        try container.encodeIfPresent(lastZeroDayKey, forKey: .lastZeroDayKey)
    }
}

/// Tracks the 8-hour daily study budget.
///
/// Time only drains while the timer is running. The timer is allowed to run
/// past the daily budget, in which case the remaining time goes negative.
/// Day rollover happens at local midnight and always leaves the timer paused
/// with a full budget.
public struct DailyTimer {
    /// Eight hours per day.
    public static let dailyBudget: TimeInterval = 8 * 60 * 60

    /// Anything longer than this between ticks is treated as sleep or a gap and
    /// is not counted, so the budget tracks actual awake time at the machine.
    private static let maximumTickGap: TimeInterval = 2

    public private(set) var counted: TimeInterval
    /// Time recorded as spent: running time plus manual subtractions.
    public private(set) var spent: TimeInterval
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

    public init(snapshot: TimerSnapshot?, now: Date, calendar: Calendar = .current) {
        let key = DailyTimer.dayKey(for: now, calendar: calendar)
        self.dayKey = key
        self.lastTick = now

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
        DailyTimer.dailyBudget - counted
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

        if wasAboveZero && remaining <= 0 {
            recordZeroReached(now: now, calendar: calendar)
        }
    }

    /// Starts a fresh day if `now` falls on a different calendar day.
    /// Returns `true` when the timer was reset.
    @discardableResult
    public mutating func handleDayChange(now: Date, calendar: Calendar = .current) -> Bool {
        let key = DailyTimer.dayKey(for: now, calendar: calendar)
        guard key != dayKey else { return false }

        dayKey = key
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
        dayKey = DailyTimer.dayKey(for: now, calendar: calendar)
        lastTick = now
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
                      isRunning: isRunning,
                      timesReachedZero: timesReachedZero,
                      currentStreak: currentStreak,
                      longestStreak: longestStreak,
                      lastZeroDayKey: lastZeroDayKey)
    }

    // MARK: - Statistics

    private mutating func recordZeroReached(now: Date, calendar: Calendar) {
        timesReachedZero += 1

        let today = DailyTimer.dayKey(for: now, calendar: calendar)
        guard lastZeroDayKey != today else { return }

        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
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

        let today = DailyTimer.dayKey(for: now, calendar: calendar)
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday = DailyTimer.dayKey(for: yesterdayDate, calendar: calendar)

        if lastZeroDayKey != today && lastZeroDayKey != yesterday {
            currentStreak = 0
        }
    }
}
