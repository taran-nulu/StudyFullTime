import Foundation

/// A snapshot of the timer that can be persisted between launches.
public struct TimerSnapshot: Codable, Equatable {
    /// Local calendar day the snapshot belongs to, formatted as `yyyy-MM-dd`.
    public var dayKey: String
    /// Seconds counted against the daily budget so far, including manual subtractions.
    public var counted: TimeInterval
    /// Whether the timer was counting down when the snapshot was taken.
    public var isRunning: Bool

    public init(dayKey: String, counted: TimeInterval, isRunning: Bool) {
        self.dayKey = dayKey
        self.counted = counted
        self.isRunning = isRunning
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
    public private(set) var isRunning: Bool
    public private(set) var dayKey: String
    private var lastTick: Date

    public init(snapshot: TimerSnapshot?, now: Date, calendar: Calendar = .current) {
        let key = DailyTimer.dayKey(for: now, calendar: calendar)
        self.dayKey = key
        self.lastTick = now

        if let snapshot = snapshot, snapshot.dayKey == key {
            self.counted = max(snapshot.counted, 0)
            self.isRunning = snapshot.isRunning
        } else {
            // First launch of the day, or the saved state is from another day.
            self.counted = 0
            self.isRunning = false
        }
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

    /// Whole minutes recorded against today's budget, including manual
    /// subtractions, rounded down. Can exceed 480.
    public var spentMinutes: Int {
        Int(max(0, counted) / 60)
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
        counted += gap
    }

    /// Starts a fresh day if `now` falls on a different calendar day.
    /// Returns `true` when the timer was reset.
    @discardableResult
    public mutating func handleDayChange(now: Date, calendar: Calendar = .current) -> Bool {
        let key = DailyTimer.dayKey(for: now, calendar: calendar)
        guard key != dayKey else { return false }

        dayKey = key
        counted = 0
        isRunning = false
        lastTick = now
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
        isRunning = false
        dayKey = DailyTimer.dayKey(for: now, calendar: calendar)
        lastTick = now
    }

    /// Marks the given number of minutes as already used. This can push the
    /// remaining time below zero and never changes the running state.
    public mutating func subtract(minutes: Int, now: Date) {
        guard minutes > 0 else { return }

        counted += TimeInterval(minutes) * 60
        lastTick = now
    }

    /// Re-anchors the tick clock without counting the elapsed gap. Used after
    /// wake-from-sleep and day-change notifications.
    public mutating func synchronize(now: Date, calendar: Calendar = .current) {
        handleDayChange(now: now, calendar: calendar)
        lastTick = now
    }

    public func snapshot() -> TimerSnapshot {
        TimerSnapshot(dayKey: dayKey, counted: counted, isRunning: isRunning)
    }
}
