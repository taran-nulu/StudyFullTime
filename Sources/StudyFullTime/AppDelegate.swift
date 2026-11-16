import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UserDefaultsTimerStore()
        let timer = DailyTimer(snapshot: store.load(), now: Date())
        let controller = StatusItemController(timer: timer, store: store)
        statusController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController?.persist()
    }
}
