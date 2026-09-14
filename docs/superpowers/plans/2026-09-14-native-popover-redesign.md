# Native Popover Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the status-bar popover start-first when idle, timer-first when active, and make shortcut controls readable and discoverable.

**Architecture:** `StatusBarController` remains the AppKit presentation boundary. A new `MenuBarPopoverView` owns adaptive SwiftUI content and receives navigation closures. A small AppKit event adapter captures a readable shortcut and passes the existing `Shortcut` value to the registration and persistence path.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Carbon hotkeys, XCTest.

---

### Task 1: Adaptive menu-bar body

**Files:**

- Create: `Sources/TopTimerApp/MenuBarPopoverView.swift`
- Modify: `Sources/TopTimerApp/StatusBarController.swift`
- Modify: `Sources/TopTimerApp/QuickEntryView.swift`
- Create: `Tests/TopTimerAppTests/MenuBarPopoverViewTests.swift`
- Modify: `Tests/TopTimerAppTests/StatusBarPopoverPresentationTests.swift`

- [ ] **Step 1: Write a failing presentation test**

```swift
func testPopoverUsesReadableBoundedSize() {
  let controller = StatusBarController(state: makeState())
  defer { controller.shutdown() }
  controller.open()
  XCTAssertEqual(controller.popoverForTesting.contentSize, NSSize(width: 320, height: 300))
}
```

- [ ] **Step 2: Verify the test fails**

Run: `swift test --filter StatusBarPopoverPresentationTests/testPopoverUsesReadableBoundedSize`

Expected: failure showing the old `(276, 240)` size.

- [ ] **Step 3: Add the adaptive view**

```swift
struct MenuBarPopoverView: View {
  @ObservedObject var state: AppState
  let openSettings: () -> Void
  let openTimers: () -> Void
  let quit: () -> Void
}
```

It always renders a focused command field and persistent text footer actions: `Settings`, `All timers`, and `Quit`. Its scrollable body is limited to 190 points. With no priority timer it shows `No timer running` plus at most three recent commands. With a priority timer it shows title, monospaced remaining time, Pause/Resume, Stop/Finish, and `Start another timer`.

- [ ] **Step 4: Route the status controller through the new view**

Set `quickEntryPopoverSize` to `NSSize(width: 320, height: 300)` and give `NSPopover`, the hosting controller, and the SwiftUI root that same contract. Remove the old inline list state from `PopoverRoot`; `All timers` opens the existing timer-list window.

- [ ] **Step 5: Verify focused tests pass**

Run: `swift test --filter 'MenuBarPopoverViewTests|StatusBarPopoverPresentationTests'`

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

Run: `git add Sources/TopTimerApp/MenuBarPopoverView.swift Sources/TopTimerApp/StatusBarController.swift Sources/TopTimerApp/QuickEntryView.swift Tests/TopTimerAppTests/MenuBarPopoverViewTests.swift Tests/TopTimerAppTests/StatusBarPopoverPresentationTests.swift && git commit -m "feat: redesign adaptive timer popover"`

### Task 2: Readable shortcut capture

**Files:**

- Create: `Sources/TopTimerApp/ShortcutRecorder.swift`
- Modify: `Sources/TopTimerApp/SettingsView.swift`
- Create: `Tests/TopTimerAppTests/ShortcutRecorderTests.swift`
- Modify: `Tests/TopTimerAppTests/Task11BehaviorTests.swift`

- [ ] **Step 1: Write failing capture tests**

```swift
func testRecorderAcceptsCommandShiftT() throws {
  XCTAssertEqual(
    try ShortcutRecorder.shortcut(keyCode: 17, modifiers: [.command, .shift]),
    Shortcut(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)))
}

func testRecorderRejectsModifierOnlyAndUnsupportedModifiers() {
  XCTAssertThrowsError(try ShortcutRecorder.shortcut(keyCode: nil, modifiers: [.command]))
  XCTAssertThrowsError(try ShortcutRecorder.shortcut(keyCode: 17, modifiers: [.function]))
}
```

- [ ] **Step 2: Verify they fail**

Run: `swift test --filter ShortcutRecorderTests`

Expected: compilation failure because `ShortcutRecorder` is absent.

- [ ] **Step 3: Implement the narrow capture boundary**

```swift
enum ShortcutRecorder {
  static func shortcut(keyCode: UInt16?, modifiers: NSEvent.ModifierFlags) throws -> Shortcut
}
```

Map only Command, Shift, Option, and Control to Carbon flags. `ShortcutCaptureSheet` owns a local monitor only while presented; it captures once, removes the monitor on all exits, and Escape/Cancel preserve the old shortcut.

- [ ] **Step 4: Replace raw shortcut rows**

Each Settings row displays the human-readable value or `Not set`, a `Change…` button, and an `Unset` button only when enabled. `Change…` opens the capture sheet with `Press the shortcut you want to use`; a valid capture calls existing `apply(_:to:)`. Conflict errors keep the registered value unchanged. Remove the numeric `TextField` and key-name table.

- [ ] **Step 5: Verify capture and unset**

Run: `swift test --filter 'ShortcutRecorderTests|Task11BehaviorTests/testUnsettingAHotkeyDisablesItAndPersistsTheChoice|SettingsStoreTests'`

Expected: all selected tests pass.

- [ ] **Step 6: Commit**

Run: `git add Sources/TopTimerApp/ShortcutRecorder.swift Sources/TopTimerApp/SettingsView.swift Tests/TopTimerAppTests/ShortcutRecorderTests.swift Tests/TopTimerAppTests/Task11BehaviorTests.swift && git commit -m "feat: add readable shortcut capture"`

### Task 3: Full verification and installed-app check

**Files:**

- Modify: `docs/decisions.md` only if delivery differs from the approved design.

- [ ] **Step 1: Run all automated tests**

Run: `swift test`

Expected: zero failures.

- [ ] **Step 2: Package and verify**

Run: `bash scripts/package-app.sh && bash scripts/verify-app.sh build/TopTimer.app`

Expected: exit 0 and `TopTimer.app verified`.

- [ ] **Step 3: Install/restart and click through**

Run: `pkill -x TopTimer || true; /usr/bin/ditto build/TopTimer.app /Applications/TopTimer.app; open -a TopTimer`

Verify idle start-entry, suggestion overflow, active pause/stop, All timers, Settings, Change shortcut, Unset, and relaunch after Unset. Record any native automation timeout as blocked rather than passed.
