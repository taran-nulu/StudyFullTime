import AppKit
import Carbon.HIToolbox
import Foundation

/// Receives raw keyboard events even while an `NSMenu` is tracking.
///
/// `NSEvent` local monitors and Carbon hotkey events are not delivered while a
/// menu is open, but a raw key event handler installed on the application
/// event target still is. Used to handle the status menu's keyboard shortcuts
/// while it is open.
final class CarbonKeyMonitor {
    private var eventHandler: EventHandlerRef?
    private let handler: (NSEvent) -> Bool

    init(handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        guard eventHandler == nil else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventRawKeyDown))

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef = eventRef, let userData = userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let monitor = Unmanaged<CarbonKeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                guard let event = NSEvent(eventRef: UnsafeRawPointer(eventRef)) else {
                    return OSStatus(eventNotHandledErr)
                }

                return monitor.handler(event) ? noErr : OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)

        if installStatus != noErr {
            eventHandler = nil
            return false
        }
        return true
    }

    func stop() {
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
