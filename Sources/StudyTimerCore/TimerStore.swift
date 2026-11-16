import Foundation

public protocol TimerStateStore {
    func load() -> TimerSnapshot?
    func save(_ snapshot: TimerSnapshot)
}

public struct UserDefaultsTimerStore: TimerStateStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = "StudyFullTime.timerSnapshot") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TimerSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TimerSnapshot.self, from: data)
    }

    public func save(_ snapshot: TimerSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
