# TopTimer Now Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TopTimer's active timer state, window-close behavior, quit behavior, and relaunch recovery obvious through a native Now window and a truthful menu-bar return path.

**Architecture:** Keep `AppState` and the Core Data repositories as the source of truth. Add a presentation-only startup recovery summary and a primary `.now` retained window. `StatusBarController` becomes a lightweight status mirror whose item and hotkey always reveal the Now window; `TopTimerApplication` owns the one quit-confirmation policy for visible and system quit routes.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Core Data, XCTest, Swift Package Manager, macOS 13.5+.

---

## File structure

- Create: `Sources/TopTimerApp/NowView.swift` — primary timer/empty/recovery surface only.
- Create: `Sources/TopTimerApp/StartupRecovery.swift` — small presentation values for launch settlement and copy selection.
- Create: `Sources/TopTimerApp/QuitPolicy.swift` — pure decision model used by visible and Command-Q quit routes.
- Modify: `Sources/TopTimerApp/AppState.swift` — settle due records before publishing launch state and expose the startup summary.
- Modify: `Sources/TopTimerApp/TopTimerApplication.swift` — retain `AppState`, reveal Now on startup, and use one confirmation route before termination.
- Modify: `Sources/TopTimerApp/StatusBarController.swift` — eliminate the transient primary popover, render a useful status title, and show the Now window.
- Modify: `Sources/TopTimerApp/WindowCoordinator.swift` — add the `.now` window while preserving singleton auxiliary-window rules.
- Modify: `Sources/TopTimerApp/StatusFormatting.swift` — format a bounded additional-timer count and accessible status label.
- Modify: `Sources/TopTimerApp/TimerListView.swift` — expose the active-list subset for Now without changing the full Timer List behavior.
- Modify: `Tests/TopTimerAppTests/AppStateTests.swift` — launch settlement and recovery tests.
- Modify: `Tests/TopTimerAppTests/LifecycleCoordinatorTests.swift` — quit policy and close sequencing tests.
- Modify: `Tests/TopTimerAppTests/StatusFormattingTests.swift` — multi-timer/status accessibility tests.
- Modify: `Tests/TopTimerAppTests/WindowCoordinatorTests.swift` — Now singleton/reopen tests.
- Create: `Tests/TopTimerAppTests/NowViewTests.swift` — rendered empty, active, paused, recovery, and warning tests.
- Create: `Tests/TopTimerAppTests/QuitPolicyTests.swift` — pure policy tests for all exit routes.
- Modify: `docs/decisions.md` — append the approved window/lifecycle decision.
- Create: `docs/full-ui-flow-audit.md` — installed-app Pass/Fail/Blocked audit matrix with screenshots and exact build identity.

### Task 1: Establish installed-app reproduction evidence

**Files:**
- Create: `docs/full-ui-flow-audit.md`

- [ ] **Step 1: Record the exact app and process identity before reproducing**

Run from `/Users/daniel/Desktop/Daniel/TopTimer`:

```bash
git rev-parse --short HEAD
pgrep -alf TopTimer || true
codesign --display --verbose=2 /Applications/TopTimer.app
```

Record the commit, bundle path, launch time, and process IDs in the audit file. Do not record timer titles or other personal content.

- [ ] **Step 2: Reproduce the current confusing route before changing code**

In the installed app: create a five-minute timer, use the visible Quit action,
wait for the process to exit, relaunch `/Applications/TopTimer.app`, and record:

1. whether the status item disappeared after quit;
2. whether `pgrep -alf TopTimer` returned no process before relaunch;
3. what first appeared after relaunch;
4. whether the active timer had a title, state, time, and reachable controls.

Mark any unavailable automation as Blocked rather than inferring a result.

- [ ] **Step 3: Add the baseline audit rows**

Create rows for first launch, active countdown, active stopwatch, paused timer,
multiple timers, close window, visible quit, Command-Q, relaunch with active
timer, relaunch after expiry, notification denial, startup failure, History,
light/dark, keyboard-only operation, and VoiceOver labels. Each row starts as
`Not run`, never `Pass`.

- [ ] **Step 4: Commit the baseline evidence**

```bash
git add docs/full-ui-flow-audit.md
git commit -m "test: document TopTimer lifecycle baseline"
```

### Task 2: Define testable launch-recovery and quit decisions

**Files:**
- Create: `Sources/TopTimerApp/StartupRecovery.swift`
- Create: `Sources/TopTimerApp/QuitPolicy.swift`
- Create: `Tests/TopTimerAppTests/QuitPolicyTests.swift`
- Modify: `Tests/TopTimerAppTests/AppStateTests.swift`

- [ ] **Step 1: Write failing pure-policy tests**

```swift
func testQuitPolicyQuitsImmediatelyWithoutActiveTimers() {
  XCTAssertEqual(QuitPolicy.decide(activeTimers: []), .quitImmediately)
}

func testQuitPolicyConfirmsWhenRunningOrPausedTimersExist() throws {
  var running = try TimerItem.countdown(title: "", duration: 60)
  try running.start(at: .now)
  var paused = try TimerItem.stopwatch(title: "")
  try paused.start(at: .now)
  try paused.pause(at: .now)
  XCTAssertEqual(QuitPolicy.decide(activeTimers: [running]), .confirmPersistence(running: 1, paused: 0))
  XCTAssertEqual(QuitPolicy.decide(activeTimers: [paused]), .confirmPersistence(running: 0, paused: 1))
}
```

Add recovery-copy tests for zero, one, and many active timers and one/many
completed-during-launch timers.

- [ ] **Step 2: Run the tests and confirm they fail because the types do not exist**

Run:

```bash
swift test --filter 'QuitPolicyTests|AppStateTests'
```

Expected: compilation failure mentioning `QuitPolicy` and `StartupRecovery`.

- [ ] **Step 3: Add bounded presentation types**

Implement values equivalent to:

```swift
public enum StartupRecovery: Equatable, Sendable {
  case none
  case activeTimers(count: Int)
  case completedWhileClosed(count: Int, activeCount: Int)
}

public enum QuitDecision: Equatable, Sendable {
  case quitImmediately
  case confirmPersistence(running: Int, paused: Int)
}
```

`QuitPolicy.decide(activeTimers:)` counts `.running` and `.paused` only. It
does not mutate domain timers and does not decide whether the user confirmed.

- [ ] **Step 4: Run the focused tests**

Run:

```bash
swift test --filter 'QuitPolicyTests|AppStateTests'
```

Expected: PASS.

- [ ] **Step 5: Commit the pure behavior**

```bash
git add Sources/TopTimerApp/StartupRecovery.swift Sources/TopTimerApp/QuitPolicy.swift Tests/TopTimerAppTests/QuitPolicyTests.swift Tests/TopTimerAppTests/AppStateTests.swift
git commit -m "feat: define TopTimer recovery and quit policy"
```

### Task 3: Settle durable timers before publishing launch state

**Files:**
- Modify: `Sources/TopTimerApp/AppState.swift`
- Modify: `Tests/TopTimerAppTests/AppStateTests.swift`

- [ ] **Step 1: Write a failing relaunch-settlement test**

Use the existing in-memory repository/recording notifications fixtures to seed a
running countdown whose deadline is before the injected `now`. Then assert:

```swift
await state.load()
XCTAssertTrue(state.activeTimers.isEmpty)
XCTAssertEqual(state.startupRecovery, .completedWhileClosed(count: 1, activeCount: 0))
XCTAssertEqual(try await repository.historyCount(for: timer.id), 1)
```

Add a second test with one expired timer and one future timer. Assert the
future timer remains active and summary is `.completedWhileClosed(count: 1,
activeCount: 1)`. Re-run `load()` and assert history remains exactly one;
completion must be idempotent.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter AppStateTests
```

Expected: failure because `load()` publishes before it settles due timers and
does not expose `startupRecovery`.

- [ ] **Step 3: Implement launch settlement without changing timer semantics**

Refactor `refresh(now:)` so it returns a bounded count of timers completed by
that invocation, while preserving its existing persistence, notification, and
recurrence sequence. In `load()`, call the settlement path before
`publishActive`, then assign `startupRecovery` exactly once from the completed
and active counts. Do not write this value to Core Data or settings.

Keep `refresh(now:)` called by the one-second scheduler, but do not replace an
already shown startup recovery message with later scheduler results.

- [ ] **Step 4: Run focused and affected regression tests**

Run:

```bash
swift test --filter 'AppStateTests|FinalIntegrationTests|NotificationDeliveryTests|Task11BehaviorTests'
```

Expected: PASS.

- [ ] **Step 5: Commit the recovery behavior**

```bash
git add Sources/TopTimerApp/AppState.swift Tests/TopTimerAppTests/AppStateTests.swift
git commit -m "feat: explain timer recovery on launch"
```

### Task 4: Add a primary Now window and remove the popover-as-home path

**Files:**
- Create: `Sources/TopTimerApp/NowView.swift`
- Modify: `Sources/TopTimerApp/WindowCoordinator.swift`
- Modify: `Sources/TopTimerApp/StatusBarController.swift`
- Modify: `Sources/TopTimerApp/TimerListView.swift`
- Modify: `Tests/TopTimerAppTests/WindowCoordinatorTests.swift`
- Create: `Tests/TopTimerAppTests/NowViewTests.swift`
- Modify: `Tests/TopTimerAppTests/StatusBarPopoverPresentationTests.swift`

- [ ] **Step 1: Write failing Now-window and coordinator tests**

Add a coordinator test proving `.now` is a singleton and reopens/raises the
same controller until the user closes that window:

```swift
let first = coordinator.show(kind: .now) { Text("Now") }
let second = coordinator.show(kind: .now) { Text("Ignored") }
XCTAssertTrue(first === second)
```

Render `NowView` with an empty `AppState` and assert the text `Start a timer`,
the entry control, three examples, and `Start` are present. Render it with a
running countdown and assert its title, `Running`, `Pause`, and `Stop` are
present. Render a paused stopwatch and assert `Paused`, `Resume`, and `Finish`.

- [ ] **Step 2: Run tests and confirm they fail**

Run:

```bash
swift test --filter 'NowViewTests|WindowCoordinatorTests|StatusBarPopoverPresentationTests'
```

Expected: compilation failure for `.now` and `NowView`; the old popover test
continues to describe behavior that this task intentionally removes.

- [ ] **Step 3: Implement the Now window**

Add `.now` to `TopTimerWindow` with a title of `TopTimer`, a minimum content
size of 460 by 360, and normal titled/closable/resizable AppKit behavior.
`NowView` owns no durable state. It receives `AppState` plus callbacks for
History, Settings, full timer list, and Quit.

Its visible hierarchy is:

```swift
VStack(alignment: .leading, spacing: 16) {
  NowToolbar(history: openHistory, settings: openSettings, quit: requestQuit)
  QuickStartEntry(state: state)
  StartupRecoveryBanner(recovery: state.startupRecovery, openHistory: openHistory)
  PrimaryTimerSummary(timer: state.priorityTimer, state: state)
  OtherActiveTimers(timers: state.activeTimers, excluding: state.priorityTimer?.id)
}
```

`PrimaryTimerSummary` has labelled text and visible action buttons. Limit
`OtherActiveTimers` to three rows and show `Show all active timers` when more
exist. Reuse existing state mutations (`pause`, `resume`, `cancel`, and
`complete`); do not duplicate domain transitions in a view. Keep the existing
Timer List as the full list and editor surface.

Change `StatusBarController` so its button action, `openFromShortcut()`, and a
new `showNow()` all call `WindowCoordinator.show(kind: .now)`. Remove
`NSPopover`, `PopoverRoot`, `showingList`, resize subscriptions, and the
popover-specific presentation test. Keep the status-item subscriptions and
shutdown behavior.

- [ ] **Step 4: Run the focused UI tests**

Run:

```bash
swift test --filter 'NowViewTests|WindowCoordinatorTests|TimerListHostTests|QuickEntryNativeRoutingTests'
```

Expected: PASS.

- [ ] **Step 5: Commit the primary surface**

```bash
git add Sources/TopTimerApp/NowView.swift Sources/TopTimerApp/WindowCoordinator.swift Sources/TopTimerApp/StatusBarController.swift Sources/TopTimerApp/TimerListView.swift Tests/TopTimerAppTests/NowViewTests.swift Tests/TopTimerAppTests/WindowCoordinatorTests.swift Tests/TopTimerAppTests/StatusBarPopoverPresentationTests.swift
git commit -m "feat: make the Now window TopTimer's primary surface"
```

### Task 5: Make the menu bar truthful and discoverable

**Files:**
- Modify: `Sources/TopTimerApp/StatusFormatting.swift`
- Modify: `Sources/TopTimerApp/StatusBarController.swift`
- Modify: `Tests/TopTimerAppTests/StatusFormattingTests.swift`

- [ ] **Step 1: Write failing status tests**

Add tests for a priority countdown plus two other active timers. Assert text
contains the priority remaining time and `+2`; assert the accessibility label
includes the priority title, `remaining`, and `2 additional active timers`.
Add a paused-only test that contains `Paused` rather than displaying a neutral
time with no state. Add an idle test with `Open TopTimer` as the accessibility
hint/tooltip.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter StatusFormattingTests
```

Expected: failure because `StatusTitleFormatter` accepts only one timer and has
no state/count language.

- [ ] **Step 3: Change the formatter boundary**

Change the formatter entry point to accept the priority timer and a bounded
`additionalActiveCount`. Do not pass all timer titles into the status item.
Format the text as a time plus ` +N` only when `N > 0`; include `Paused` when
the priority timer is paused. Set `item.button?.toolTip` to `Open TopTimer` and
set an accessibility label that names the state and count. Keep text bounded to
one priority timer and a decimal count.

- [ ] **Step 4: Run the focused tests**

Run:

```bash
swift test --filter StatusFormattingTests
```

Expected: PASS.

- [ ] **Step 5: Commit status behavior**

```bash
git add Sources/TopTimerApp/StatusFormatting.swift Sources/TopTimerApp/StatusBarController.swift Tests/TopTimerAppTests/StatusFormattingTests.swift
git commit -m "feat: clarify active timers in the menu bar"
```

### Task 6: Route all quit requests through one persistence confirmation

**Files:**
- Modify: `Sources/TopTimerApp/TopTimerApplication.swift`
- Modify: `Sources/TopTimerApp/NowView.swift`
- Modify: `Sources/TopTimerApp/StatusBarController.swift`
- Modify: `Tests/TopTimerAppTests/LifecycleCoordinatorTests.swift`
- Modify: `Tests/TopTimerAppTests/QuitPolicyTests.swift`

- [ ] **Step 1: Write failing confirmation-sequencing tests**

Test that a no-active-timer request reaches `LifecycleCoordinator.requestTermination()`.
Test that an active-timer request returns a confirmation decision before
`operations.stopAccepting()` runs. Test an explicit confirm result causes one
termination attempt and a cancel result causes none. Reuse the pure
`QuitPolicy` and a small injected `QuitConfirmationPresenting` protocol so
AppKit alerts are not unit-tested directly.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter 'QuitPolicyTests|LifecycleCoordinatorTests'
```

Expected: failure because the visible button calls `NSApplication.terminate`
directly and there is no common confirmation boundary.

- [ ] **Step 3: Implement the common request path**

Retain `AppState` in `TopTimerApplication` after successful startup. Give
`StatusBarController`/`NowView` an injected `requestQuit` closure rather than
calling `NSApplication.shared.terminate(nil)` in a SwiftUI view. In
`applicationShouldTerminate`, evaluate `QuitPolicy` unless an explicit
confirmation flag is set.

For `.confirmPersistence`, present a native `NSAlert` with this exact intent:

```text
Title: Keep active timers running?
Message: TopTimer will close. Running timers continue toward their saved end time; paused timers stay paused. You can control them when you open TopTimer again.
Buttons: Cancel; Quit and keep timers
```

Cancel replies to AppKit with `false`. Confirmation sets the one-shot flag and
calls `NSApp.terminate(nil)` again, which then proceeds through the existing
drain/store-close flow. Never cancel notification requests, timers, or sleep
independently of the existing shutdown code. Reset the one-shot confirmation
flag if termination fails.

- [ ] **Step 4: Run quit and lifecycle tests**

Run:

```bash
swift test --filter 'QuitPolicyTests|LifecycleCoordinatorTests|OperationOwnerTests'
```

Expected: PASS.

- [ ] **Step 5: Commit lifecycle work**

```bash
git add Sources/TopTimerApp/TopTimerApplication.swift Sources/TopTimerApp/NowView.swift Sources/TopTimerApp/StatusBarController.swift Tests/TopTimerAppTests/LifecycleCoordinatorTests.swift Tests/TopTimerAppTests/QuitPolicyTests.swift
git commit -m "feat: confirm persistent timers before quitting"
```

### Task 7: Launch Now visibly and document the decision

**Files:**
- Modify: `Sources/TopTimerApp/TopTimerApplication.swift`
- Modify: `docs/decisions.md`
- Modify: `Tests/TopTimerAppTests/FinalIntegrationTests.swift`

- [ ] **Step 1: Write a failing startup composition test**

At the application composition seam, inject a status/window presenter and
assert startup calls `showNow()` after `await state.load()` succeeds. Add a
failure-path assertion that startup failure does not attempt to create Now.

- [ ] **Step 2: Run the composition test and verify it fails**

Run:

```bash
swift test --filter FinalIntegrationTests
```

Expected: failure because successful startup creates only the status item.

- [ ] **Step 3: Reveal the Now window after successful state loading**

After `await state.load()`, controller construction, hotkey registration, and
the lifecycle `createResources` effect, assign the controller and call
`controller.showNow(focusEntry: state.activeTimers.isEmpty)`. Do not activate
or create the Now window in failure/closing paths.

Append a dated decision to `docs/decisions.md`: the primary window is the
default visible surface; the menu bar mirrors state; window-close hides only;
quit persists timers after explicit confirmation; all timer/domain semantics
remain unchanged. State that changing this would require a product decision to
stop timers on quit.

- [ ] **Step 4: Run startup regressions**

Run:

```bash
swift test --filter 'FinalIntegrationTests|LifecycleCoordinatorTests|WindowCoordinatorTests'
```

Expected: PASS.

- [ ] **Step 5: Commit startup visibility and decision ledger**

```bash
git add Sources/TopTimerApp/TopTimerApplication.swift Tests/TopTimerAppTests/FinalIntegrationTests.swift docs/decisions.md
git commit -m "feat: open TopTimer Now window on launch"
```

### Task 8: Full verification and installed-app audit

**Files:**
- Modify: `docs/full-ui-flow-audit.md`

- [ ] **Step 1: Run static and full automated verification**

Run:

```bash
swift test
swift build -c release
```

Expected: both commands exit 0 with no warnings. If either fails, stop and use
`superpowers:systematic-debugging` before changing production code.

- [ ] **Step 2: Package and install the exact verified build**

Read and run the repository's existing packaging command from `README.md` or
`scripts/`; do not invent a second installer. Record its exact command and
result in the audit. Verify the installed binary and current build have the
same SHA-256 digest before UI testing.

- [ ] **Step 3: Perform the installed-app audit**

Use `/Applications/TopTimer.app`, not a test host. For every baseline row from
Task 1, record Pass, Fail, or Blocked plus a screenshot or short reproducible
note. Explicitly test:

1. first launch and all three examples;
2. countdown and stopwatch creation;
3. pause, resume, stop, finish, close window, and menu-bar return;
4. several active timers and the `+N` status title;
5. visible quit cancellation and confirmation, actual process exit, relaunch
   with active timer, and relaunch after expiry;
6. notification denied, notification delivered, notification action, and
   relaunch recovery;
7. History navigation after a completion, light/dark, keyboard-only flow,
   VoiceOver labels, resizing, and error/retry states.

Do not mark an unexercised state as Pass because unit tests pass.

- [ ] **Step 4: Commit final evidence only if every required check is recorded**

```bash
git add docs/full-ui-flow-audit.md
git commit -m "test: audit TopTimer now window flows"
```

If any condition remains Blocked, commit the evidence with the blocker and
report the product as partially verified rather than complete.

## Plan self-review

- Design coverage: Tasks 2-3 implement recovery; 4-5 implement Now/status
  discoverability; 6 implements all quit routes; 7 starts the visible primary
  surface; 8 covers installed behavior and accessibility.
- Scope: parsing, timer persistence schema, recurrence, history format, and
  notification authorization remain unchanged.
- Safety: durable completion remains repository-owned and idempotent; quitting
  never cancels active timers by implication; all additions are bounded.
- Handoff: pre-existing uncommitted work in the repository is outside this
  feature. The implementer must preserve it or work in a new worktree before
  editing source files.
