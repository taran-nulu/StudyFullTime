# StudyFullTime

A macOS menu bar timer for an 8-hour daily study budget.

The status bar always shows the remaining time in whole minutes, e.g. `480m`.
Click it for pause/resume controls. The timer refills at local midnight and
starts each new day paused.

## Behavior

- **8 hours per day.** The countdown shows minutes only (`480m` → `479m` → … → `0m`), rounded up.
- **Pause / resume** from the dropdown menu, or reset today's timer back to `480m`.
- **Subtract time on demand.** Choose **Subtract Minutes...**, enter any positive number of minutes, and that time is marked as used. Subtracting more than what remains stops the timer at `0m`.
- **Time spent today.** The dropdown shows the total budget used today, in whole minutes. Manually subtracted minutes count here too, so subtracting 230 minutes immediately shows `230 min` spent while reducing the remaining time.
- **Resets at midnight** to a full, paused budget. It also resets when the app notices the calendar day changed while running.
- **Only counts while the Mac is awake and the app is running.** Sleep gaps and time with the app quit do not consume the budget.
- **Persists across restarts.** The counted time and paused/running state are saved in `UserDefaults`, so relaunching within the same day picks up where you left off.
- No Dock icon or app switcher entry; it lives only in the menu bar.
- When the budget reaches zero it stays at `0m` until midnight or a manual reset.

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

- Daily budget: `DailyTimer.dailyBudget` in `Sources/StudyTimerCore/DailyTimer.swift`.
- Sleep/gap tolerance: `maximumTickGap` in the same file.
- After changing either, run `make app` again.

## Layout

```
Sources/StudyTimerCore/DailyTimer.swift       timer state machine and minute formatting
Sources/StudyTimerCore/TimerStore.swift       UserDefaults persistence
Sources/StudyFullTime/main.swift              AppKit entry point
Sources/StudyFullTime/AppDelegate.swift       app lifecycle
Sources/StudyFullTime/StatusItemController.swift  menu bar item and menu
Tests/main.swift                              standalone timer-core checks
scripts/build-app.sh                          assembles and signs the .app bundle
```
