import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private var timer: DailyTimer
    private let store: TimerStateStore

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let spentItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
    private let subtractItem = NSMenuItem(title: "Subtract Minutes...", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "Reset Today's Timer", action: nil, keyEquivalent: "")

    private var ticker: Timer?
    private var lastTitle = ""
    private var lastPersistDate = Date.distantPast

    init(timer: DailyTimer, store: TimerStateStore) {
        self.timer = timer
        self.store = store
        super.init()
        configureStatusItem()
        configureMenu()
    }

    deinit {
        ticker?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func start() {
        registerObservers()
        refresh()
        persist()

        let ticker = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.handleTick()
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func persist() {
        store.save(timer.snapshot())
        lastPersistDate = Date()
    }

    // MARK: - Setup

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "hourglass",
                                accessibilityDescription: "Study time remaining")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.toolTip = "Study time remaining today"
            button.attributedTitle = attributedTitle(for: timer.displayText)
        }
        statusItem.menu = menu
    }

    private func configureMenu() {
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        spentItem.isEnabled = false
        menu.addItem(spentItem)

        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(toggleTimer)
        menu.addItem(toggleItem)

        subtractItem.target = self
        subtractItem.action = #selector(subtractMinutes)
        menu.addItem(subtractItem)

        resetItem.target = self
        resetItem.action = #selector(resetTimer)
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit StudyFullTime",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
    }

    private func registerObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self,
                                    selector: #selector(systemWillSleep),
                                    name: NSWorkspace.willSleepNotification,
                                    object: nil)
        workspaceCenter.addObserver(self,
                                    selector: #selector(systemDidWake),
                                    name: NSWorkspace.didWakeNotification,
                                    object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(dayDidChange),
                                               name: .NSCalendarDayChanged,
                                               object: nil)
    }

    // MARK: - Ticking

    private func handleTick() {
        let now = Date()
        timer.tick(now: now)
        refresh()

        if now.timeIntervalSince(lastPersistDate) >= 10 {
            persist()
        }
    }

    private func refresh() {
        let title = timer.displayText
        if title != lastTitle {
            lastTitle = title
            statusItem.button?.attributedTitle = attributedTitle(for: title)
        }

        let minutes = timer.minutesRemaining
        if minutes > 0 {
            headerItem.title = "\(minutes) min remaining today"
        } else if minutes < 0 {
            headerItem.title = "Over by \(-minutes) min"
        } else {
            headerItem.title = "Time's up for today"
        }
        spentItem.title = "Time spent today: \(timer.spentMinutes) min"

        toggleItem.title = timer.isRunning ? "Pause" : "Resume"
    }

    private func attributedTitle(for text: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                  weight: .regular)
        return NSAttributedString(string: text, attributes: [.font: font])
    }

    // MARK: - Menu actions

    @objc private func toggleTimer() {
        timer.toggle(now: Date())
        persist()
        refresh()
    }

    @objc private func resetTimer() {
        timer.reset(now: Date())
        persist()
        refresh()
    }

    @objc private func subtractMinutes() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Subtract Minutes"
        alert.informativeText = "Enter how many minutes to subtract from today's remaining time."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Subtract")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Minutes"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(text), minutes > 0 else {
            NSSound.beep()
            return
        }

        timer.subtract(minutes: minutes, now: Date())
        persist()
        refresh()
    }

    @objc private func quit() {
        persist()
        NSApp.terminate(nil)
    }

    // MARK: - System notifications

    @objc private func systemWillSleep() {
        persist()
    }

    @objc private func systemDidWake() {
        timer.synchronize(now: Date())
        persist()
        refresh()
    }

    @objc private func dayDidChange() {
        timer.synchronize(now: Date())
        persist()
        refresh()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }
}
