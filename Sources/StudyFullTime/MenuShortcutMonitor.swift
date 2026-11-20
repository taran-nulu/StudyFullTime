import AppKit
import Foundation

/// Watches for the menu's keyboard shortcuts while an `NSMenu` is tracking.
///
/// Menu tracking runs its own event loop, and an inactive `LSUIElement` app does
/// not receive AppKit's normal key-equivalent handling. A raw Carbon key handler
/// still receives those events; matching them against the tracked menu's own key
/// equivalents lets the shortcuts work regardless of which app was active.
/// Returning `eventNotHandledErr` for keys it does not match lets arrows, Return,
/// Escape, and type-to-select reach the menu unchanged. An `NSEvent` local
/// monitor is kept as a fallback on newer systems.
final class MenuShortcutMonitor {
    private let menu: NSMenu
    private let perform: (NSMenuItem) -> Void

    private var appKitMonitor: AnyObject?
    private var carbonMonitor: CarbonKeyMonitor?
    private var isStarted = false

    init(menu: NSMenu, perform: @escaping (NSMenuItem) -> Void) {
        self.menu = menu
        self.perform = perform
    }

    deinit {
        stop()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let monitor = CarbonKeyMonitor { [weak self] event in
            guard let self = self,
                  let item = self.matchingItem(for: event) else {
                return false
            }
            self.perform(item)
            return true
        }
        monitor.start()
        carbonMonitor = monitor

        if #available(macOS 14.0, *) {
            appKitMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self = self,
                      let item = self.matchingItem(for: event) else {
                    return event
                }
                self.perform(item)
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

    /// Finds the menu item whose shortcut matches `event`, if any.
    private func matchingItem(for event: NSEvent) -> NSMenuItem? {
        guard event.type == .keyDown,
              let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return nil
        }

        let flags = normalizedModifiers(event.modifierFlags)

        return menu.items.first { item in
            guard !item.isSeparatorItem,
                  item.action != nil,
                  item.isEnabled,
                  !item.keyEquivalent.isEmpty else {
                return false
            }
            guard normalizedModifiers(item.keyEquivalentModifierMask) == flags else {
                return false
            }
            return item.keyEquivalent.compare(characters,
                                              options: .caseInsensitive) == .orderedSame
        }
    }

    private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad])
    }
}
