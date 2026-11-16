import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private var timer: DailyTimer
    private let store: TimerStateStore

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
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
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(toggleTimer)
        menu.addItem(toggleItem)

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

        headerItem.title = timer.isFinished
            ? "Time's up for today"
            : "\(timer.minutesRemaining) min remaining today"

        toggleItem.title = timer.isRunning ? "Pause" : "Resume"
        toggleItem.isEnabled = !timer.isFinished
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
