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

/// A small window for changing the daily study budget.
final class SettingsWindowController: NSWindowController {
    /// Called with the new budget in whole minutes when the user saves.
    var onSave: ((Int) -> Void)?

    private let budgetField = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "")

    init() {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                                    styleMask: [.titled, .closable],
                                    backing: .buffered,
                                    defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the window with the current budget filled in.
    func present(budgetMinutes: Int) {
        budgetField.stringValue = "\(budgetMinutes)"
        errorLabel.stringValue = ""

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(budgetField)
        budgetField.selectText(nil)
    }

    // MARK: - Layout

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

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

        let root = NSStackView(views: [fieldRow, hintLabel, errorLabel, buttonRow])
        root.orientation = .vertical
        root.spacing = 10
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

    // MARK: - Actions

    @objc private func save() {
        let text = budgetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minutes = Int(text), (1...1440).contains(minutes) else {
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
}
