import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let now = Date()
        let store = UserDefaultsTimerStore()
        let timer = DailyTimer(snapshot: store.load(), now: now)
        let taskStore = UserDefaultsTaskStore()
        let tasks = TaskList(snapshot: taskStore.load(), now: now)
        let controller = StatusItemController(timer: timer,
                                              store: store,
                                              tasks: tasks,
                                              taskStore: taskStore)
        statusController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController?.shutdown()
    }
}
