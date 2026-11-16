import Foundation

/// A single to-do item with its accumulated working time.
public struct StudyTask: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    /// Seconds accumulated while the task was running.
    public var elapsed: TimeInterval
    /// Whether the task is selected for timing. Time only accumulates while
    /// the study timer is also running.
    public var isRunning: Bool

    public init(id: UUID = UUID(),
                title: String,
                isCompleted: Bool = false,
                elapsed: TimeInterval = 0,
                isRunning: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.elapsed = max(0, elapsed)
        self.isRunning = isRunning && !isCompleted
    }

    /// Whole minutes spent on the task, rounded down.
    public var elapsedMinutes: Int {
        Int(max(0, elapsed) / 60)
    }
}

/// Persisted task list.
public struct TaskSnapshot: Codable, Equatable {
    public var tasks: [StudyTask]

    public init(tasks: [StudyTask]) {
        self.tasks = tasks
    }
}

/// Tracks a small to-do list and how long each task has been worked on.
///
/// Task clocks only advance while `tick(now:isActive:)` reports that the study
/// timer is running, so pausing the study timer also pauses task time. Running
/// tasks are always stopped when the list is loaded, which gives pause-on-quit
/// behavior even after a crash or force quit.
public struct TaskList {
    /// Anything longer than this between ticks is treated as sleep or a gap and
    /// is not counted.
    private static let maximumTickGap: TimeInterval = 2

    public private(set) var tasks: [StudyTask]
    private var lastTick: Date

    public init(snapshot: TaskSnapshot?, now: Date) {
        // Pause-on-quit: never resume a timer from a previous process.
        self.tasks = (snapshot?.tasks ?? []).map { task in
            var task = task
            task.elapsed = max(0, task.elapsed)
            task.isRunning = false
            return task
        }
        self.lastTick = now
    }

    public var runningTask: StudyTask? {
        tasks.first(where: { $0.isRunning })
    }

    public var hasCompletedTasks: Bool {
        tasks.contains(where: { $0.isCompleted })
    }

    /// Appends a trimmed, non-empty task. Returns `nil` when the title is blank.
    @discardableResult
    public mutating func add(title: String, now: Date) -> StudyTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let task = StudyTask(title: trimmed)
        tasks.append(task)
        lastTick = now
        return task
    }

    public mutating func delete(id: UUID, now: Date) {
        accumulate(now: now)
        tasks.removeAll { $0.id == id }
        lastTick = now
    }

    /// Removes every completed task and leaves active tasks untouched.
    public mutating func clearCompleted(now: Date) {
        accumulate(now: now)
        tasks.removeAll { $0.isCompleted }
        lastTick = now
    }

    /// Removes every task, completed or not.
    public mutating func deleteAll(now: Date) {
        accumulate(now: now)
        tasks.removeAll()
        lastTick = now
    }

    /// Marks a task complete without deleting it. Completing a running task
    /// stops its clock.
    public mutating func setCompleted(_ completed: Bool, id: UUID, now: Date) {
        accumulate(now: now)
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].isCompleted = completed
            if completed {
                tasks[index].isRunning = false
            }
        }
        lastTick = now
    }

    public mutating func toggleCompleted(id: UUID, now: Date) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        setCompleted(!task.isCompleted, id: id, now: now)
    }

    /// Starts timing a task. Any other running task is stopped first.
    public mutating func start(id: UUID, now: Date) {
        accumulate(now: now)

        if let index = tasks.firstIndex(where: { $0.id == id }),
           !tasks[index].isCompleted {
            for other in tasks.indices {
                tasks[other].isRunning = (other == index)
            }
        }
        lastTick = now
    }

    public mutating func stop(id: UUID, now: Date) {
        accumulate(now: now)
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].isRunning = false
        }
        lastTick = now
    }

    public mutating func stopAll(now: Date) {
        accumulate(now: now)
        for index in tasks.indices {
            tasks[index].isRunning = false
        }
        lastTick = now
    }

    /// Advances the running task's clock. `isActive` reflects whether the study
    /// timer is running; when false, elapsed time is frozen.
    public mutating func tick(now: Date, isActive: Bool) {
        defer { lastTick = now }
        guard isActive else { return }

        accumulate(now: now)
    }

    /// Re-anchors the tick clock without counting the elapsed gap. Used after
    /// wake-from-sleep and day-change notifications.
    public mutating func synchronize(now: Date) {
        lastTick = now
    }

    public func snapshot() -> TaskSnapshot {
        TaskSnapshot(tasks: tasks)
    }

    private mutating func accumulate(now: Date) {
        guard let index = tasks.firstIndex(where: { $0.isRunning }) else { return }

        let delta = now.timeIntervalSince(lastTick)
        guard delta > 0 else { return }

        let gap = min(delta, TaskList.maximumTickGap)
        tasks[index].elapsed += gap
    }
}
