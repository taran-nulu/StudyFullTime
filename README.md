# StudyFullTime

A macOS menu bar timer for a configurable daily study budget (8 hours by default).

The status bar always shows the remaining time in whole minutes, e.g. `480m`.
Click it for pause/resume controls. The timer refills at the configured daily
reset time (midnight by default) and starts each new day paused.

## Behavior

- **8 hours per day by default.** The countdown shows minutes only (`480m` → `479m` → … → `0m`), rounded up. If the timer keeps running past the budget, it goes negative (`-1m`, `-2m`, …). Choose **Settings…** (**⌘,**) to change the daily budget and reset time; time already counted is kept, and the new settings apply to today and future days.
- **Pause / resume** from the dropdown menu, or reset today's timer back to `480m`. The menu bar icon changes with the state: an hourglass while running and `moon.zzz` while paused.
- **Subtract time on demand.** Choose **Subtract Minutes...**, enter any positive number of minutes, and that time is marked as used. Subtracting more than what remains can also push the countdown negative.
- **Add time on demand.** Choose **Add Minutes...**, enter any positive number of minutes, and the remaining time increases immediately. Additions can take the countdown above the configured daily budget and never change time spent.
- **Time spent today.** The dropdown shows total spent time in whole minutes: running time plus manual subtractions. Manually added minutes are excluded, so adding time never lowers the spent figure. It can exceed the daily budget.
- **Zero and streak stats.** The dropdown shows how many times the countdown has reached zero, the current daily streak, and the longest streak. A streak counts consecutive calendar days on which zero was reached at least once; reaching zero several times in one day does not extend it. A streak stays current through the day after the last zero and then expires if no new zero occurs. The longest streak is kept forever.
- **Stats page.** Choose **Settings…** (**⌘,**) and open **Stats** to see overall time spent studying across every tracked day, plus today's total, lifetime times completed, the longest streak, and the number of days studied. The lifetime totals accumulate as you study and are kept across days and restarts.
- **Tasks.** Choose **Tasks…** or press **⌘T** to open the task window. Add tasks, check them off to complete them, delete individual tasks, use **Delete Completed** to clear finished ones, or **Delete All** to remove every task after confirming. Completed tasks stay in the list until deleted. **Start** a task to track its minutes; **Stop** or completing it freezes the clock. While a task is running, the **Tasks…** row shows its name and tracked minutes. Task time only advances while the study timer is running, and a task is paused when the app quits.
- **Resets at midnight by default.** The daily reset time can be changed in **Settings…** (for example, to 1 AM). The timer refills then and starts paused; a running timer is stopped. Streaks stay current until the day after the last zero, measured from the configured reset time, so a late-night session still counts toward the same day.
- **Only counts while the Mac is awake and the app is running.** Sleep gaps and time with the app quit do not consume the budget.
- **Persists across restarts.** The counted time, paused/running state, and all-time study total are saved in `UserDefaults`, so relaunching within the same day picks up where you left off.
- No Dock icon or app switcher entry; it lives only in the menu bar.
- The timer never stops itself at zero. Negative time only appears after a full minute of overrun, and a paused overrun timer can be resumed.

## Keyboard shortcuts

While the dropdown menu is open:

| Action | Shortcut |
| --- | --- |
| Open tasks | ⌘T |
| Pause / Resume | ⌘P |
| Add minutes | ⌘A |
| Subtract minutes | ⌘S |
| Reset today's timer | ⌘R |
| Settings | ⌘, |
| Quit | ⌘Q |

While the Tasks window is focused, **⌘P** pauses or resumes the study timer, **⌘,** opens Settings, and **⌘W** closes the window.

From any app: **⌃⌥M** opens the StudyFullTime menu without clicking the icon, and pressing it again closes the menu. It uses a system-wide hotkey, so no Accessibility permission is required.

## Build and run

Requires macOS 11+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
make test   # compile and run the timer-core checks
make run    # build .build/StudyFullTime.app and launch it
```

Other targets:

```sh
make app      # bundle the app without launching it
make debug    # unoptimized build at .build/StudyFullTime-debug
make install  # copy the app to ~/Applications
make clean    # remove build artifacts
```

To start it automatically, add `StudyFullTime.app` under **System Settings →
General → Login Items**.

### Note on the build

This machine has only the Command Line Tools, and its SwiftPM installation is
missing `xctest`, so `swift build` / `swift test` fail before compiling. The
Makefile therefore invokes `swiftc` directly and uses a small standalone test
harness instead of XCTest. All sources remain plain Swift, so the project can be
moved to an Xcode/SwiftPM toolchain later if desired.

## Customizing

- Daily budget: change it in **Settings…**, or edit the default `DailyTimer.dailyBudget` in `Sources/StudyTimerCore/DailyTimer.swift`.
- Sleep/gap tolerance: `maximumTickGap` in the same file.
- After changing either, run `make app` again.

## Layout

```
Sources/StudyTimerCore/DailyTimer.swift       timer state machine and minute formatting
Sources/StudyTimerCore/TaskList.swift         task list and per-task time tracking
Sources/StudyTimerCore/TimerStore.swift       UserDefaults persistence
Sources/StudyTimerCore/TaskStore.swift        task persistence
Sources/StudyFullTime/main.swift              AppKit entry point
Sources/StudyFullTime/AppDelegate.swift       app lifecycle
Sources/StudyFullTime/GlobalHotKey.swift      system-wide shortcut support
Sources/StudyFullTime/StatusItemController.swift  menu bar item and menu
Sources/StudyFullTime/TasksWindowController.swift task window UI
Sources/StudyFullTime/SettingsWindowController.swift settings window UI
Tests/main.swift                              standalone timer-core checks
scripts/build-app.sh                          assembles and signs the .app bundle
```
