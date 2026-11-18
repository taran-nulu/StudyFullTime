import AppKit
import Foundation

/// Watches for a shortcut while an `NSMenu` is tracking.
///
/// Menu tracking runs its own event loop and consumes key events before the
/// menu's normal key-equivalent handling. A raw Carbon key handler still
/// receives those events, and returning `eventNotHandledErr` for keys it does
/// not match lets them reach the menu unchanged. An `NSEvent` local monitor is
/// kept as a fallback on newer systems.
final class MenuShortcutMonitor {
    private let matches: (NSEvent) -> Bool
    private let action: () -> Void

    private var appKitMonitor: AnyObject?
    private var carbonMonitor: CarbonKeyMonitor?
    private var isStarted = false

    init(matches: @escaping (NSEvent) -> Bool, action: @escaping () -> Void) {
        self.matches = matches
        self.action = action
    }

    deinit {
        stop()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let monitor = CarbonKeyMonitor { [weak self] event in
            guard let self = self, self.matches(event) else { return false }
            self.action()
            return true
        }
        monitor.start()
        carbonMonitor = monitor

        if #available(macOS 14.0, *) {
            appKitMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self = self, self.matches(event) else { return event }
                self.action()
                return nil
            } as AnyObject
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        if let appKitMonitor = appKitMonitor {
            NSEvent.removeMonitor(appKitMonitor)
            self.appKitMonitor = nil
        }

        carbonMonitor?.stop()
        carbonMonitor = nil
    }
}
