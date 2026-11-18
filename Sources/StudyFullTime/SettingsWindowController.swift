import AppKit

/// The settings window closes on ⌘W even though the app has no main menu.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A small window with General and Stats pages.
final class SettingsWindowController: NSWindowController {
    /// Called with the new budget in whole minutes when the user saves.
    var onSave: ((Int) -> Void)?

    private let pageControl = NSSegmentedControl(labels: ["Stats", "General"],
                                                 trackingMode: .selectOne,
                                                 target: nil,
                                                 action: nil)
    private let generalPage = NSStackView()
    private let statsPage = NSStackView()
    private let budgetField = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "")
    private let allTimeValue = NSTextField(labelWithString: "0 min")
    private let todayValue = NSTextField(labelWithString: "0 min")
    private let timesValue = NSTextField(labelWithString: "0")
    private let longestStreakValue = NSTextField(labelWithString: "0 days")
    private let daysValue = NSTextField(labelWithString: "0")

    init() {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 310),
                                    styleMask: [.titled, .closable],
                                    backing: .buffered,
                                    defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.setFrameAutosaveName("StudyFullTime.SettingsWindow")
        window.center()
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the window with the current budget and statistics filled in.
    func present(budgetMinutes: Int,
                 totalSpentMinutes: Int,
                 todaySpentMinutes: Int,
                 timesReachedZero: Int,
                 longestStreak: Int,
                 daysStudied: Int) {
        budgetField.stringValue = "\(budgetMinutes)"
        errorLabel.stringValue = ""
        updateStats(totalSpentMinutes: totalSpentMinutes,
                    todaySpentMinutes: todaySpentMinutes,
                    timesReachedZero: timesReachedZero,
                    longestStreak: longestStreak,
                    daysStudied: daysStudied)
        show(page: 0)

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Updates the Stats page without touching the budget field.
    func updateStats(totalSpentMinutes: Int,
                     todaySpentMinutes: Int,
                     timesReachedZero: Int,
                     longestStreak: Int,
                     daysStudied: Int) {
        allTimeValue.stringValue = SettingsWindowController.durationText(
            minutes: totalSpentMinutes)
        todayValue.stringValue = "\(todaySpentMinutes) min"
        timesValue.stringValue = "\(timesReachedZero)"
        longestStreakValue.stringValue = longestStreak == 1
            ? "1 day"
            : "\(longestStreak) days"
        daysValue.stringValue = "\(daysStudied)"
    }

    // MARK: - Layout

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        pageControl.target = self
        pageControl.action = #selector(changePage)
        pageControl.selectedSegment = 0
        pageControl.setContentHuggingPriority(.required, for: .horizontal)

        let pageRow = NSStackView(views: [pageControl, NSView()])
        pageRow.orientation = .horizontal
        pageRow.distribution = .fill

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 176).isActive = true
        addPage(generalPage, to: container)
        addPage(statsPage, to: container)

        buildGeneralPage()
        buildStatsPage()

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let buttonRow = NSStackView(views: [NSView(), buttons])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill

        let root = NSStackView(views: [pageRow, container, buttonRow])
        root.orientation = .vertical
        root.spacing = 14
        root.alignment = .width
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    private func addPage(_ page: NSStackView, to container: NSView) {
        page.orientation = .vertical
        page.alignment = .width
        page.spacing = 10
        page.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(page)

        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: container.topAnchor),
            page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            page.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
    }

    private func buildGeneralPage() {
        let titleLabel = NSTextField(labelWithString: "Daily budget (minutes)")
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize)

        budgetField.alignment = .right
        budgetField.target = self
        budgetField.action = #selector(save)
        budgetField.setContentHuggingPriority(.required, for: .horizontal)
        budgetField.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let fieldRow = NSStackView(views: [titleLabel, budgetField])
        fieldRow.orientation = .horizontal
        fieldRow.spacing = 12
        fieldRow.alignment = .centerY
        fieldRow.distribution = .fill

        let hintLabel = NSTextField(labelWithString:
            "Applies to today and every new day. Time already counted is kept.")
        hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 2
        hintLabel.lineBreakMode = .byWordWrapping

        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 1

        generalPage.addArrangedSubview(fieldRow)
        generalPage.addArrangedSubview(hintLabel)
        generalPage.addArrangedSubview(errorLabel)
    }

    private func buildStatsPage() {
        let caption = NSTextField(labelWithString: "Overall time spent studying")
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor

        allTimeValue.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        allTimeValue.textColor = .labelColor

        let todayCaption = NSTextField(labelWithString: "Today")
        todayCaption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        todayCaption.textColor = .secondaryLabelColor

        todayValue.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                     weight: .regular)
        todayValue.alignment = .right

        let todayRow = NSStackView(views: [todayCaption, NSView(), todayValue])
        todayRow.orientation = .horizontal
        todayRow.distribution = .fill
        todayRow.alignment = .firstBaseline

        statsPage.addArrangedSubview(caption)
        statsPage.addArrangedSubview(allTimeValue)
        statsPage.addArrangedSubview(todayRow)
        statsPage.addArrangedSubview(statRow("Times completed", value: timesValue))
        statsPage.addArrangedSubview(statRow("Longest streak", value: longestStreakValue))
        statsPage.addArrangedSubview(statRow("Days studied", value: daysValue))
    }

    private func statRow(_ title: String, value: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)

        value.alignment = .right
        value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                weight: .regular)

        let row = NSStackView(views: [label, NSView(), value])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .firstBaseline
        return row
    }

    // MARK: - Pages

    private func show(page: Int) {
        pageControl.selectedSegment = page
        statsPage.isHidden = page != 0
        generalPage.isHidden = page != 1
    }

    @objc private func changePage() {
        show(page: pageControl.selectedSegment)
    }

    // MARK: - Actions

    @objc private func save() {
        let text = budgetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(text), (1...1440).contains(minutes) else {
            show(page: 1)
            errorLabel.stringValue = "Enter a whole number from 1 to 1440."
            NSSound.beep()
            window?.makeFirstResponder(budgetField)
            budgetField.selectText(nil)
            return
        }

        onSave?(minutes)
        window?.performClose(nil)
    }

    @objc private func cancel() {
        window?.performClose(nil)
    }

    /// Formats whole minutes as hours and minutes, e.g. `12h 34m` or `0h 34m`.
    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours)h \(remainder)m"
    }
}
