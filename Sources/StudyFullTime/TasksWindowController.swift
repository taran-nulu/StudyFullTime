import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The task window closes itself on ⌘W and toggles the study timer on ⌘P even
/// though the app has no main menu.
private final class TasksWindow: NSWindow {
    var onToggleTimer: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == .command,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "w":
            performClose(nil)
            return true
        case "p":
            onToggleTimer?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

protocol TasksWindowControllerDelegate: AnyObject {
    func tasksForWindow() -> [StudyTask]
    func isStudyTimerRunningForWindow() -> Bool
    func tasksWindowDidAdd(title: String)
    func tasksWindowDidDelete(id: UUID)
    func tasksWindowDidToggleCompleted(id: UUID)
    func tasksWindowDidStart(id: UUID)
    func tasksWindowDidStop(id: UUID)
    func tasksWindowDidClearCompleted()
    func tasksWindowDidDeleteAll()
    func tasksWindowDidToggleTimer()
}

/// A reusable window that lists tasks and exposes add, complete, delete,
/// start, and stop controls.
final class TasksWindowController: NSWindowController {
    weak var delegate: TasksWindowControllerDelegate?

    private let addField = NSTextField()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let listView = FlippedView()
    private let listStack = NSStackView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "Delete Completed", target: nil, action: nil)
    private let deleteAllButton = NSButton(title: "Delete All", target: nil, action: nil)

    private var rowViews: [UUID: TaskRowView] = [:]
    private var lastSignature: [TaskRowSignature] = []
    private var studyTimerRunning = false

    init() {
        let window = TasksWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered,
                                 defer: false)
        window.title = "Tasks"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 380, height: 280)
        super.init(window: window)
        window.onToggleTimer = { [weak self] in
            self?.delegate?.tasksWindowDidToggleTimer()
        }
        window.setFrameAutosaveName("StudyFullTime.TasksWindow")
        window.center()
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        guard let delegate = delegate else { return }
        update(tasks: delegate.tasksForWindow(),
               isStudyTimerRunning: delegate.isStudyTimerRunningForWindow())
    }

    // MARK: - Layout

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        addField.placeholderString = "New task"
        addField.target = self
        addField.action = #selector(addTask)

        addButton.target = self
        addButton.action = #selector(addTask)
        addButton.bezelStyle = .rounded

        let addRow = NSStackView(views: [addField, addButton])
        addRow.orientation = .horizontal
        addRow.spacing = 8
        addRow.alignment = .centerY
        addRow.distribution = .fill
        addRow.setContentHuggingPriority(.required, for: .vertical)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.translatesAutoresizingMaskIntoConstraints = false

        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.addSubview(listStack)
        scrollView.documentView = listView

        let fitViewport = listView.heightAnchor.constraint(
            equalTo: scrollView.contentView.heightAnchor)
        fitViewport.priority = .defaultLow

        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: listView.topAnchor, constant: 6),
            listStack.leadingAnchor.constraint(equalTo: listView.leadingAnchor, constant: 4),
            listStack.trailingAnchor.constraint(equalTo: listView.trailingAnchor, constant: -4),
            listView.heightAnchor.constraint(greaterThanOrEqualTo: listStack.heightAnchor,
                                             constant: 12),
            listView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            fitViewport,
            listView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        clearButton.target = self
        clearButton.action = #selector(clearCompleted)
        clearButton.bezelStyle = .rounded
        clearButton.isEnabled = false

        deleteAllButton.target = self
        deleteAllButton.action = #selector(deleteAllTasks)
        deleteAllButton.bezelStyle = .rounded
        deleteAllButton.isEnabled = false

        let footerButtons = NSStackView(views: [clearButton, deleteAllButton])
        footerButtons.orientation = .horizontal
        footerButtons.spacing = 8
        footerButtons.alignment = .centerY

        let footer = NSStackView(views: [summaryLabel, footerButtons])
        footer.orientation = .horizontal
        footer.distribution = .equalSpacing
        footer.alignment = .centerY
        footer.setContentHuggingPriority(.required, for: .vertical)

        let root = NSStackView(views: [addRow, scrollView, footer])
        root.orientation = .vertical
        root.spacing = 12
        root.alignment = .width
        root.distribution = .fill
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    // MARK: - Updating

    private struct TaskRowSignature: Equatable {
        let id: UUID
        let title: String
        let isCompleted: Bool
        let isRunning: Bool
    }

    private func update(tasks: [StudyTask], isStudyTimerRunning: Bool) {
        studyTimerRunning = isStudyTimerRunning

        let signature = tasks.map {
            TaskRowSignature(id: $0.id,
                             title: $0.title,
                             isCompleted: $0.isCompleted,
                             isRunning: $0.isRunning)
        }

        if signature != lastSignature {
            rebuildRows(tasks: tasks)
            lastSignature = signature
        } else {
            for task in tasks {
                rowViews[task.id]?.updateElapsed(task: task,
                                                 studyTimerRunning: isStudyTimerRunning)
            }
        }

        let completedCount = tasks.filter { $0.isCompleted }.count
        clearButton.isEnabled = completedCount > 0
        clearButton.title = completedCount > 0
            ? "Delete Completed (\(completedCount))"
            : "Delete Completed"
        deleteAllButton.isEnabled = !tasks.isEmpty
        summaryLabel.stringValue = tasks.isEmpty
            ? ""
            : "\(tasks.count) task\(tasks.count == 1 ? "" : "s")"
    }

    private func rebuildRows(tasks: [StudyTask]) {
        for view in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowViews.removeAll()

        guard !tasks.isEmpty else {
            let empty = NSTextField(labelWithString: "No tasks yet. Add one above.")
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            listStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            return
        }

        for task in tasks {
            let row = TaskRowView(task: task)
            row.onToggleCompleted = { [weak self] in
                self?.delegate?.tasksWindowDidToggleCompleted(id: task.id)
                self?.refresh()
            }
            row.onStartStop = { [weak self] in
                guard let self = self else { return }
                if task.isRunning {
                    self.delegate?.tasksWindowDidStop(id: task.id)
                } else {
                    self.delegate?.tasksWindowDidStart(id: task.id)
                }
                self.refresh()
            }
            row.onDelete = { [weak self] in
                self?.delegate?.tasksWindowDidDelete(id: task.id)
                self?.refresh()
            }

            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            rowViews[task.id] = row
        }

        for task in tasks {
            rowViews[task.id]?.updateElapsed(task: task,
                                             studyTimerRunning: studyTimerRunning)
        }
    }

    // MARK: - Actions

    @objc private func addTask() {
        let title = addField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            NSSound.beep()
            return
        }

        delegate?.tasksWindowDidAdd(title: title)
        addField.stringValue = ""
        window?.makeFirstResponder(addField)
        refresh()
    }

    @objc private func clearCompleted() {
        delegate?.tasksWindowDidClearCompleted()
        refresh()
    }

    @objc private func deleteAllTasks() {
        guard delegate?.tasksForWindow().isEmpty == false else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Delete all tasks?"
        alert.informativeText = "This removes every task and its tracked time. It cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        delegate?.tasksWindowDidDeleteAll()
        refresh()
    }
}

/// A single row in the tasks window.
private final class TaskRowView: NSView {
    let taskID: UUID

    var onToggleCompleted: (() -> Void)?
    var onStartStop: (() -> Void)?
    var onDelete: (() -> Void)?

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")
    private let spacer = NSView()
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let startStopButton = NSButton(title: "Start", target: nil, action: nil)
    private let deleteButton = NSButton(title: "", target: nil, action: nil)

    init(task: StudyTask) {
        self.taskID = task.id
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        checkbox.target = self
        checkbox.action = #selector(toggleCompleted)

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        elapsedLabel.alignment = .right
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize,
                                                       weight: .regular)
        elapsedLabel.textColor = .secondaryLabelColor
        elapsedLabel.setContentHuggingPriority(.required, for: .horizontal)
        elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true

        startStopButton.target = self
        startStopButton.action = #selector(startStop)
        startStopButton.bezelStyle = .rounded
        startStopButton.setContentHuggingPriority(.required, for: .horizontal)
        startStopButton.widthAnchor.constraint(equalToConstant: 64).isActive = true

        deleteButton.image = NSImage(systemSymbolName: "trash",
                                     accessibilityDescription: "Delete task")
        deleteButton.imagePosition = .imageOnly
        deleteButton.isBordered = false
        deleteButton.toolTip = "Delete task"
        deleteButton.target = self
        deleteButton.action = #selector(deleteTask)
        deleteButton.setContentHuggingPriority(.required, for: .horizontal)
        deleteButton.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let stack = NSStackView(views: [checkbox, titleLabel, spacer, elapsedLabel,
                                        startStopButton, deleteButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        update(task: task, studyTimerRunning: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(task: StudyTask, studyTimerRunning: Bool) {
        checkbox.state = task.isCompleted ? .on : .off

        let color: NSColor = task.isCompleted ? .secondaryLabelColor : .labelColor
        titleLabel.attributedStringValue = NSAttributedString(
            string: task.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: color,
                .strikethroughStyle: task.isCompleted
                    ? NSUnderlineStyle.single.rawValue
                    : 0,
            ])

        startStopButton.title = task.isRunning ? "Stop" : "Start"
        startStopButton.isEnabled = !task.isCompleted
        updateElapsed(task: task, studyTimerRunning: studyTimerRunning)
    }

    func updateElapsed(task: StudyTask, studyTimerRunning: Bool) {
        var text = "\(task.elapsedMinutes) min"
        if task.isRunning && !studyTimerRunning {
            text += " (paused)"
        }
        elapsedLabel.stringValue = text
    }

    @objc private func toggleCompleted() {
        onToggleCompleted?()
    }

    @objc private func startStop() {
        onStartStop?()
    }

    @objc private func deleteTask() {
        onDelete?()
    }
}
