import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private var timer: DailyTimer
    private let store: TimerStateStore
    private var tasks: TaskList
    private let taskStore: TaskStateStore
    private var tasksWindowController: TasksWindowController?
    private var settingsWindowController: SettingsWindowController?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let spentItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let zeroCountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let streakItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let shortcutItem = NSMenuItem(title: "Open/close menu",
                                          action: nil,
                                          keyEquivalent: "")
    /// Hidden item that actually handles ⌃⌥M while the menu is open. The
    /// visible row above is disabled, so it only displays the shortcut.
    private let closeMenuShortcutItem = NSMenuItem(title: "Close Menu",
                                                   action: nil,
                                                   keyEquivalent: "")
    private let tasksItem = NSMenuItem(title: "Tasks…", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
    private let addItem = NSMenuItem(title: "Add Minutes...", action: nil, keyEquivalent: "")
    private let subtractItem = NSMenuItem(title: "Subtract Minutes...", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "Reset Today's Timer", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: "")

    private var ticker: Timer?
    private let globalHotKey = GlobalHotKey()
    private lazy var menuShortcutMonitor = MenuShortcutMonitor(
        matches: { event in
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad])
            return event.keyCode == UInt16(GlobalHotKey.controlOptionMKeyCode)
                && flags == [.control, .option]
        },
        action: { [weak self] in
            self?.menu.cancelTracking()
        })
    private var lastTitle = ""
    private var lastSymbolName: String?
    private var lastPersistDate = Date.distantPast
    private var isMenuOpen = false
    private var lastMenuCloseDate = Date.distantPast

    init(timer: DailyTimer,
         store: TimerStateStore,
         tasks: TaskList,
         taskStore: TaskStateStore) {
        self.timer = timer
        self.store = store
        self.tasks = tasks
        self.taskStore = taskStore
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
        registerGlobalHotKey()
        refresh()
        persist()
        persistTasks()

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

    func persistTasks() {
        taskStore.save(tasks.snapshot())
    }

    /// Stops any running task (pause-on-quit) and saves everything.
    func shutdown() {
        menuShortcutMonitor.stop()
        globalHotKey.unregister()
        tasks.stopAll(now: Date())
        persist()
        persistTasks()
    }

    // MARK: - Setup

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.toolTip = "Study time remaining today"
            button.attributedTitle = attributedTitle(for: timer.displayText)
        }
        updateStatusImageIfNeeded()
        statusItem.menu = menu
    }

    /// Shows an hourglass while the timer is running and a sleeping moon while
    /// it is paused. The image is only replaced when the state changes.
    private func updateStatusImageIfNeeded() {
        let symbolName = timer.isRunning ? "hourglass" : "moon.zzz"
        guard symbolName != lastSymbolName else { return }
        lastSymbolName = symbolName

        let description = timer.isRunning
            ? "Study timer running"
            : "Study timer paused"
        let image = NSImage(systemSymbolName: symbolName,
                            accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "hourglass",
                       accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func configureMenu() {
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        spentItem.isEnabled = false
        menu.addItem(spentItem)

        menu.addItem(.separator())

        zeroCountItem.isEnabled = false
        menu.addItem(zeroCountItem)

        streakItem.isEnabled = false
        menu.addItem(streakItem)

        menu.addItem(.separator())

        tasksItem.target = self
        tasksItem.action = #selector(showTasks)
        tasksItem.keyEquivalent = "t"
        tasksItem.keyEquivalentModifierMask = .command
        menu.addItem(tasksItem)

        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(toggleTimer)
        toggleItem.keyEquivalent = "p"
        toggleItem.keyEquivalentModifierMask = .command
        menu.addItem(toggleItem)

        addItem.target = self
        addItem.action = #selector(addMinutes)
        addItem.keyEquivalent = "a"
        addItem.keyEquivalentModifierMask = .command
        menu.addItem(addItem)

        subtractItem.target = self
        subtractItem.action = #selector(subtractMinutes)
        subtractItem.keyEquivalent = "s"
        subtractItem.keyEquivalentModifierMask = .command
        menu.addItem(subtractItem)

        resetItem.target = self
        resetItem.action = #selector(resetTimer)
        resetItem.keyEquivalent = "r"
        resetItem.keyEquivalentModifierMask = .command
        menu.addItem(resetItem)

        menu.addItem(.separator())

        closeMenuShortcutItem.target = self
        closeMenuShortcutItem.action = #selector(closeMenuShortcut)
        closeMenuShortcutItem.keyEquivalent = "m"
        closeMenuShortcutItem.keyEquivalentModifierMask = [.control, .option]
        closeMenuShortcutItem.isHidden = true
        closeMenuShortcutItem.allowsKeyEquivalentWhenHidden = true
        menu.addItem(closeMenuShortcutItem)

        shortcutItem.isEnabled = false
        shortcutItem.keyEquivalent = "m"
        shortcutItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(shortcutItem)

        settingsItem.target = self
        settingsItem.action = #selector(showSettings)
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit StudyFullTime",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
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

    private func registerGlobalHotKey() {
        let registered = globalHotKey.register(
            keyCode: GlobalHotKey.controlOptionMKeyCode,
            modifiers: GlobalHotKey.controlOptionMModifiers
        ) { [weak self] in
            self?.openMenuFromHotKey()
        }

        if !registered {
            NSLog("StudyFullTime: could not register the Control-Option-M shortcut")
        }
    }

    /// Opens the same dropdown the status item shows when clicked, or closes
    /// it when the menu is already open.
    private func openMenuFromHotKey() {
        if isMenuOpen {
            statusItem.menu?.cancelTracking()
            return
        }

        // Delivering the hotkey makes the system dismiss an open menu, and
        // this handler can run just after that. Don't immediately reopen it.
        if Date().timeIntervalSince(lastMenuCloseDate) < 0.3 {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        if let button = statusItem.button, button.window != nil {
            button.performClick(nil)
            return
        }

        guard let menu = statusItem.menu else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - Ticking

    private func handleTick() {
        let now = Date()
        let previousZeroCount = timer.timesReachedZero
        let previousDayKey = timer.dayKey

        timer.tick(now: now)
        tasks.tick(now: now, isActive: timer.isRunning)
        refresh()

        // Zero crossings and day rollovers must be saved immediately so a
        // streak is not lost if the app quits before the next periodic save.
        let statsChanged = timer.timesReachedZero != previousZeroCount
        let dayChanged = timer.dayKey != previousDayKey
        if statsChanged || dayChanged || now.timeIntervalSince(lastPersistDate) >= 10 {
            persist()
            persistTasks()
        }
    }

    private func refresh() {
        updateStatusImageIfNeeded()

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
        zeroCountItem.title = "Times completed: \(timer.timesReachedZero)"
        streakItem.title = "Streak: \(dayCount(timer.currentStreak))"
            + " · Longest: \(dayCount(timer.longestStreak))"
        if let running = tasks.runningTask {
            let name = running.title.count > 40
                ? String(running.title.prefix(39)) + "…"
                : running.title
            let pausedSuffix = timer.isRunning ? "" : " (paused)"
            tasksItem.title = "Tasks — \(name) · "
                + "\(running.elapsedMinutes) min\(pausedSuffix)"
        } else {
            tasksItem.title = "Tasks…"
        }

        toggleItem.title = timer.isRunning ? "Pause" : "Resume"

        if let tasksWindowController = tasksWindowController,
           tasksWindowController.window?.isVisible == true {
            tasksWindowController.refresh()
        }

        if let settingsWindowController = settingsWindowController,
           settingsWindowController.window?.isVisible == true {
            settingsWindowController.updateStats(
                totalSpentMinutes: timer.lifetimeSpentMinutes,
                todaySpentMinutes: timer.spentMinutes,
                timesReachedZero: timer.timesReachedZero,
                longestStreak: timer.longestStreak,
                daysStudied: timer.daysStudied)
        }
    }

    private func dayCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "day" : "days")"
    }

    private func attributedTitle(for text: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                  weight: .regular)
        return NSAttributedString(string: text, attributes: [.font: font])
    }

    // MARK: - Menu actions

    @objc private func showTasks() {
        if tasksWindowController == nil {
            let controller = TasksWindowController()
            controller.delegate = self
            tasksWindowController = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        tasksWindowController?.showWindow(nil)
        tasksWindowController?.window?.makeKeyAndOrderFront(nil)
        tasksWindowController?.refresh()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController()
            controller.onSave = { [weak self] minutes, resetMinutes in
                guard let self = self else { return }
                let now = Date()
                self.timer.setBudget(minutes: minutes, now: now)
                self.timer.setResetTime(minutes: resetMinutes, now: now)
                self.persist()
                self.refresh()
            }
            settingsWindowController = controller
        }

        settingsWindowController?.present(budgetMinutes: timer.budgetMinutes,
                                          resetMinutes: timer.resetMinutes,
                                          totalSpentMinutes: timer.lifetimeSpentMinutes,
                                          todaySpentMinutes: timer.spentMinutes,
                                          timesReachedZero: timer.timesReachedZero,
                                          longestStreak: timer.longestStreak,
                                          daysStudied: timer.daysStudied)
    }

    @objc private func closeMenuShortcut() {
        statusItem.menu?.cancelTracking()
    }

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

    @objc private func addMinutes() {
        promptForMinutes(title: "Add Minutes",
                         message: "Enter how many minutes to add to today's remaining time.",
                         buttonTitle: "Add") { minutes, now in
            self.timer.add(minutes: minutes, now: now)
        }
    }

    @objc private func subtractMinutes() {
        promptForMinutes(title: "Subtract Minutes",
                         message: "Enter how many minutes to subtract from today's remaining time.",
                         buttonTitle: "Subtract") { minutes, now in
            self.timer.subtract(minutes: minutes, now: now)
        }
    }

    private func promptForMinutes(title: String,
                                  message: String,
                                  buttonTitle: String,
                                  apply: (Int, Date) -> Void) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: buttonTitle)
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

        apply(minutes, Date())
        persist()
        refresh()
    }

    @objc private func quit() {
        shutdown()
        NSApp.terminate(nil)
    }

    // MARK: - System notifications

    @objc private func systemWillSleep() {
        persist()
        persistTasks()
    }

    @objc private func systemDidWake() {
        let now = Date()
        timer.synchronize(now: now)
        tasks.synchronize(now: now)
        persist()
        persistTasks()
        refresh()
    }

    @objc private func dayDidChange() {
        let now = Date()
        timer.synchronize(now: now)
        tasks.synchronize(now: now)
        persist()
        persistTasks()
        refresh()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        // Carbon hotkeys are not delivered while the menu tracks, so hand the
        // shortcut over to a raw key monitor until the menu closes.
        globalHotKey.suspend()
        menuShortcutMonitor.start()
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        menuShortcutMonitor.stop()
        globalHotKey.resume()
        lastMenuCloseDate = Date()
    }
}

// MARK: - TasksWindowControllerDelegate

extension StatusItemController: TasksWindowControllerDelegate {
    func tasksForWindow() -> [StudyTask] {
        tasks.tasks
    }

    func isStudyTimerRunningForWindow() -> Bool {
        timer.isRunning
    }

    func tasksWindowDidAdd(title: String) {
        tasks.add(title: title, now: Date())
        persistTasks()
        refresh()
    }

    func tasksWindowDidDelete(id: UUID) {
        tasks.delete(id: id, now: Date())
        persistTasks()
        refresh()
    }

    func tasksWindowDidToggleCompleted(id: UUID) {
        tasks.toggleCompleted(id: id, now: Date())
        persistTasks()
        refresh()
    }

    func tasksWindowDidStart(id: UUID) {
        tasks.start(id: id, now: Date())
        persistTasks()
        refresh()
    }

    func tasksWindowDidStop(id: UUID) {
        tasks.stop(id: id, now: Date())
        persistTasks()
        refresh()
    }

    func tasksWindowDidClearCompleted() {
        tasks.clearCompleted(now: Date())
        persistTasks()
        refresh()
    }

    func tasksWindowDidDeleteAll() {
        tasks.deleteAll(now: Date())
        persistTasks()
        refresh()
    }

    func tasksWindowDidToggleTimer() {
        toggleTimer()
    }

    func tasksWindowDidRequestSettings() {
        showSettings()
    }
}
