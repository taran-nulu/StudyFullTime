import Foundation

/// A snapshot of the timer that can be persisted between launches.
public struct TimerSnapshot: Codable, Equatable {
    /// Local calendar day the snapshot belongs to, formatted as `yyyy-MM-dd`.
    public var dayKey: String
    /// Seconds counted against the daily budget so far.
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
/// Time only drains while the timer is running. Day rollover happens at local
/// midnight and always leaves the timer paused with a full budget.
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
            let restored = min(max(snapshot.counted, 0), DailyTimer.dailyBudget)
            self.counted = restored
            self.isRunning = snapshot.isRunning && restored < DailyTimer.dailyBudget
        } else {
            // First launch of the day, or the saved state is from another day.
            self.counted = 0
            self.isRunning = false
        }
    }

    /// Seconds left in today's budget.
    public var remaining: TimeInterval {
        max(0, DailyTimer.dailyBudget - counted)
    }

    public var isFinished: Bool {
        remaining <= 0
    }

    /// Remaining time in whole minutes, rounded up so a full day reads 480.
    public var minutesRemaining: Int {
        DailyTimer.minutes(from: remaining)
    }

    /// Compact text for the menu bar, e.g. `480m`.
    public var displayText: String {
        DailyTimer.minutesText(from: remaining)
    }

    public static func minutes(from remaining: TimeInterval) -> Int {
        guard remaining > 0 else { return 0 }
        return Int(ceil(remaining / 60))
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

        counted = min(DailyTimer.dailyBudget, counted + min(delta, DailyTimer.maximumTickGap))
        if counted >= DailyTimer.dailyBudget {
            isRunning = false
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
        isRunning = false
        lastTick = now
        return true
    }

    /// Pauses or resumes. Resuming is ignored once the budget is used up.
    public mutating func setRunning(_ running: Bool, now: Date) {
        isRunning = running && !isFinished
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
