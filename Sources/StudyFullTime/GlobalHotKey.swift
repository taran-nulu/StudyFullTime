import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey registered through Carbon. Unlike event taps, this
/// does not require Accessibility permission.
final class GlobalHotKey {
    static let controlOptionMKeyCode = UInt32(kVK_ANSI_M)
    static let controlOptionMModifiers = UInt32(controlKey | optionKey)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?
    private var keyCode: UInt32?
    private var modifiers: UInt32?

    @discardableResult
    func register(keyCode: UInt32,
                  modifiers: UInt32,
                  handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler
        self.keyCode = keyCode
        self.modifiers = modifiers

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData = userData else { return noErr }
                Unmanaged<GlobalHotKey>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .invoke()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)

        guard installStatus == noErr else {
            unregister()
            return false
        }

        guard installHotKey() else {
            unregister()
            return false
        }
        return true
    }

    private func installHotKey() -> Bool {
        guard let keyCode = keyCode, let modifiers = modifiers else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5346544D), id: 1)
        let registerStatus = RegisterEventHotKey(keyCode,
                                                 modifiers,
                                                 hotKeyID,
                                                 GetEventDispatcherTarget(),
                                                 0,
                                                 &hotKeyRef)
        return registerStatus == noErr
    }

    /// Temporarily stops registering the shortcut, for example while a menu is
    /// tracking and a local monitor handles the key instead.
    func suspend() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func resume() {
        guard hotKeyRef == nil, handler != nil else { return }
        if !installHotKey() {
            NSLog("StudyFullTime: could not re-register the Control-Option-M shortcut")
        }
    }

    func unregister() {
        suspend()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handler = nil
        keyCode = nil
        modifiers = nil
    }

    deinit {
        unregister()
    }

    private func invoke() {
        handler?()
    }
}
