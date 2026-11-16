import Foundation

public protocol TaskStateStore {
    func load() -> TaskSnapshot?
    func save(_ snapshot: TaskSnapshot)
}

public struct UserDefaultsTaskStore: TaskStateStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = "StudyFullTime.tasks") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TaskSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TaskSnapshot.self, from: data)
    }

    public func save(_ snapshot: TaskSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
