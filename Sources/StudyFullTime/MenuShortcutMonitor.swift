import AppKit
import Foundation

/// Watches for a shortcut while an `NSMenu` is tracking.
///
/// Menu tracking runs its own event loop and consumes key events before a
/// regular local monitor sees them. On macOS 14 and later a run-loop observer
/// in event-tracking mode catches the key first; older systems use a Carbon
/// raw key handler, which also runs during menu tracking.
final class MenuShortcutMonitor {
    private let matches: (NSEvent) -> Bool
    private let action: () -> Void

    private var appKitMonitor: AnyObject?
    private var runLoopObserver: CFRunLoopObserver?
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

        if #available(macOS 14.0, *) {
            startRunLoopObserver()
            appKitMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self = self, self.matches(event) else { return event }
                self.action()
                return nil
            } as AnyObject
        } else {
            let monitor = CarbonKeyMonitor { [weak self] event in
                guard let self = self, self.matches(event) else { return false }
                self.action()
                return true
            }
            monitor.start()
            carbonMonitor = monitor
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        if let appKitMonitor = appKitMonitor {
            NSEvent.removeMonitor(appKitMonitor)
            self.appKitMonitor = nil
        }

        if let runLoopObserver = runLoopObserver {
            CFRunLoopRemoveObserver(CFRunLoopGetCurrent(),
                                    runLoopObserver,
                                    CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
            self.runLoopObserver = nil
        }

        carbonMonitor?.stop()
        carbonMonitor = nil
    }

    /// Handles key events that reach the head of the event-tracking queue
    /// before the menu consumes them.
    private func startRunLoopObserver() {
        let observer = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.beforeSources.rawValue,
            true,
            0
        ) { [weak self] _, _ in
            guard let self = self else { return }

            var unhandled: [NSEvent] = []
            while let head = NSApp.nextEvent(matching: .any,
                                             until: nil,
                                             inMode: .eventTracking,
                                             dequeue: false),
                  head.type == .keyDown,
                  let event = NSApp.nextEvent(matching: [.keyDown],
                                              until: nil,
                                              inMode: .eventTracking,
                                              dequeue: true) {
                if self.matches(event) {
                    self.action()
                } else {
                    unhandled.append(event)
                }
            }

            for event in unhandled.reversed() {
                NSApp.postEvent(event, atStart: true)
            }
        }

        CFRunLoopAddObserver(CFRunLoopGetCurrent(),
                             observer,
                             CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
        runLoopObserver = observer
    }
}
