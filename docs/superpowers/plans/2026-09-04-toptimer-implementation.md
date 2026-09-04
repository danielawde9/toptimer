# TopTimer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, verify, package, install, and launch the complete open-source
TopTimer macOS menu-bar timer described in the approved specification.

**Architecture:** A dependency-free Swift Package separates deterministic timer
domain behavior, Core Data persistence, macOS system integrations, and the
SwiftUI/AppKit application shell. The engine stores absolute dates rather than
decrementing counters, and all external effects sit behind protocols so tests use
controlled clocks and temporary stores.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Core Data, UserNotifications, Charts,
ServiceManagement, Carbon, IOKit, XCTest, Swift Package Manager, shell packaging.

---

## File map

Create these focused files:

- `Package.swift` — products, targets, platform floor, warning settings.
- `LICENSE` — MIT license.
- `Sources/TopTimerDomain/TimerModels.swift` — timer, recurrence, metadata, and
  history value types.
- `Sources/TopTimerDomain/TimerParser.swift` — bounded natural-language parser.
- `Sources/TopTimerDomain/RecurrenceCalculator.swift` — next-date calculation.
- `Sources/TopTimerDomain/TimerEngine.swift` — state transitions and priority.
- `Sources/TopTimerDomain/HistoryAnalytics.swift` — bounded filtering and totals.
- `Sources/TopTimerDomain/CSVExporter.swift` — stable RFC 4180 export.
- `Sources/TopTimerPersistence/CoreDataModel.swift` — programmatic managed model.
- `Sources/TopTimerPersistence/CoreDataStore.swift` — persistent container setup.
- `Sources/TopTimerPersistence/TimerRepository.swift` — atomic timer/history I/O.
- `Sources/TopTimerSystem/NotificationController.swift` — authorization,
  scheduling, categories, and action routing.
- `Sources/TopTimerSystem/AlertSoundController.swift` — import and playback.
- `Sources/TopTimerSystem/GlobalHotKeyController.swift` — bounded Carbon hotkeys.
- `Sources/TopTimerSystem/LoginItemController.swift` — launch-at-login state.
- `Sources/TopTimerSystem/SleepAssertionController.swift` — one owned IOPM
  assertion.
- `Sources/TopTimerApp/TopTimerApp.swift` — app lifecycle and composition root.
- `Sources/TopTimerApp/AppState.swift` — observable application state.
- `Sources/TopTimerApp/StatusBarController.swift` — status item and popover.
- `Sources/TopTimerApp/QuickEntryView.swift` — fast entry and compact toolbar.
- `Sources/TopTimerApp/TimerListView.swift` — bounded running-timer list.
- `Sources/TopTimerApp/TimerEditorView.swift` — metadata, sound, recurrence.
- `Sources/TopTimerApp/HistoryView.swift` — search, edit, recovery, pagination.
- `Sources/TopTimerApp/ReportsView.swift` — date totals and Charts output.
- `Sources/TopTimerApp/SettingsView.swift` — display and system preferences.
- `Sources/TopTimerApp/WindowCoordinator.swift` — retained auxiliary windows.
- `Sources/TopTimerApp/Resources/Info.plist` — bundle metadata source.
- `scripts/generate-icon.swift` — original TopTimer app-icon raster generation.
- `scripts/package-app.sh` — release build and `.app` assembly.
- `scripts/verify-app.sh` — bundle and installed-process smoke gate.
- `README.md`, `CONTRIBUTING.md`, `docs/architecture.md` — handover material.

Tests mirror source responsibilities under `Tests/TopTimerDomainTests`,
`Tests/TopTimerPersistenceTests`, `Tests/TopTimerSystemTests`, and
`Tests/TopTimerAppTests`.

### Task 1: Package scaffold and bounded domain models

**Files:**
- Create: `Package.swift`
- Create: `LICENSE`
- Create: `Sources/TopTimerDomain/TopTimerDomain.swift`
- Create: `Sources/TopTimerDomain/TimerModels.swift`
- Test: `Tests/TopTimerDomainTests/TimerModelsTests.swift`

- [ ] **Step 1: Create the package shell and a failing model test**

Use `swift-tools-version: 6.0`, `.macOS(.v13)`, and one library target plus its
test target. Add an empty public module marker, then add this test before defining
`TimerItem`:

```swift
import XCTest
@testable import TopTimerDomain

final class TimerModelsTests: XCTestCase {
    func testCountdownRejectsNonPositiveDuration() {
        XCTAssertThrowsError(
            try TimerItem.countdown(title: "Tea", duration: 0)
        )
    }

    func testMetadataLimitsAreEnforced() throws {
        let item = try TimerItem.stopwatch(
            title: String(repeating: "T", count: 80),
            details: String(repeating: "D", count: 500),
            tags: (0..<12).map { "tag\($0)" }
        )
        XCTAssertEqual(item.details.count, 500)
        XCTAssertEqual(item.tags.count, 12)
    }
}
```

- [ ] **Step 2: Run the model test and verify RED**

Run: `swift test --filter TimerModelsTests`
Expected: compilation fails because `TimerItem` is not defined.

- [ ] **Step 3: Implement the value types and invariants**

Define `TimerKind`, `TimerState`, `CompletionReason`, `RecurrenceRule`,
`TimerItem`, and `HistoryEntry` as `Codable`, `Equatable`, `Sendable` values.
Use throwing factories with these fixed boundaries:

```swift
public enum TimerValidationError: Error, Equatable {
    case nonPositiveDuration
    case titleTooLong
    case descriptionTooLong
    case tooManyTags
    case tagTooLong
}

public struct TimerLimits: Sendable {
    public static let title = 80
    public static let details = 500
    public static let tags = 12
    public static let tag = 32
}
```

Countdowns require `duration > 0`; stopwatches store no duration. Preserve the
empty title because quick entry may intentionally start an unnamed timer.

- [ ] **Step 4: Run all tests and verify GREEN**

Run: `swift test`
Expected: `TimerModelsTests` passes with zero warnings.

- [ ] **Step 5: Commit the green model step**

```bash
git add Package.swift LICENSE Sources/TopTimerDomain Tests/TopTimerDomainTests
git commit -m "feat: add bounded timer domain models"
```

### Task 2: Natural-language timer parser

**Files:**
- Create: `Sources/TopTimerDomain/TimerParser.swift`
- Test: `Tests/TopTimerDomainTests/TimerParserTests.swift`

- [ ] **Step 1: Write parser examples as failing table tests**

```swift
func testParsesSupportedDurationsAndMetadata() throws {
    let parser = TimerParser(calendar: utcCalendar, now: fixedNow)
    let cases: [(String, TimeInterval)] = [
        ("15", 900), ("60s", 60), ("1.5h", 5_400),
        ("1h 20m", 4_800), ("1:30:45", 5_445)
    ]
    for (input, seconds) in cases {
        XCTAssertEqual(try parser.parse(input).duration, seconds)
    }
    let parsed = try parser.parse("25m Design review #client #ui")
    XCTAssertEqual(parsed.title, "Design review")
    XCTAssertEqual(parsed.tags, ["client", "ui"])
}

func testBlankInputCreatesStopwatch() throws {
    XCTAssertEqual(try parser.parse("   ").kind, .stopwatch)
}

func testInputIsBounded() {
    XCTAssertThrowsError(try parser.parse(String(repeating: "x", count: 2_049)))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter TimerParserTests`
Expected: compilation fails because `TimerParser` is missing.

- [ ] **Step 3: Implement a single-pass bounded parser**

Expose this API:

```swift
public struct ParsedTimer: Equatable, Sendable {
    public let kind: TimerKind
    public let duration: TimeInterval?
    public let deadline: Date?
    public let title: String
    public let tags: [String]
}

public struct TimerParser: Sendable {
    public init(calendar: Calendar = .current, now: Date = .now)
    public func parse(_ input: String) throws -> ParsedTimer
}
```

Cap input at 2,048 Unicode scalar values and numeric results at 365 days. Parse
`@` wall-clock values first, colon forms second, and unit tokens third. Treat a
bare positive number as minutes. Reject unknown numeric suffixes, duplicate unit
tokens, negative values, NaN, infinity, and overflow.

- [ ] **Step 4: Add wall-clock, 12/24-hour, Unicode, and rejection tests**

Include fixed-calendar tests for `@3pm`, `@14:30`, next-day rollover, apostrophes,
mixed scripts in titles, 13 tags, 33-character tags, and a 366-day duration.

- [ ] **Step 5: Run all tests and commit**

Run: `swift test`
Expected: all parser and model tests pass with zero warnings.

```bash
git add Sources/TopTimerDomain/TimerParser.swift Tests/TopTimerDomainTests/TimerParserTests.swift
git commit -m "feat: parse natural-language timers"
```

### Task 3: Deterministic timer engine and priority

**Files:**
- Create: `Sources/TopTimerDomain/TimerEngine.swift`
- Test: `Tests/TopTimerDomainTests/TimerEngineTests.swift`

- [ ] **Step 1: Write failing state-transition tests**

```swift
func testSleepDoesNotIntroduceCountdownDrift() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    var timer = try TimerItem.countdown(title: "Focus", duration: 60)
    timer.start(at: start)
    XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(45)), 15)
    XCTAssertTrue(timer.isDue(at: start.addingTimeInterval(61)))
}

func testPauseAndResumePreserveRemainingTime() throws {
    let start = Date(timeIntervalSince1970: 2_000)
    var timer = try TimerItem.countdown(title: "Focus", duration: 60)
    timer.start(at: start)
    timer.pause(at: start.addingTimeInterval(20))
    timer.resume(at: start.addingTimeInterval(200))
    XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(210)), 30)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter TimerEngineTests`
Expected: compilation fails because transition methods are missing.

- [ ] **Step 3: Implement explicit transitions and priority selection**

Use mutating methods that throw `TimerTransitionError` for invalid state changes.
Implement `remaining(at:)` from `deadline - now`, never from a stored ticking
counter. Add:

```swift
public enum TimerPriority {
    public static func select(from timers: [TimerItem], at now: Date) -> TimerItem? {
        let running = timers.filter { $0.state == .running }
        let countdowns = running.filter { $0.kind == .countdown }
        return countdowns.min { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            ?? running.min { ($0.startedAt ?? .distantFuture) < ($1.startedAt ?? .distantFuture) }
    }
}
```

- [ ] **Step 4: Test simultaneous timers and every transition**

Cover start, pause, resume, restart, complete-once, acknowledge, duplicate,
stopwatch elapsed time, completed visibility, and priority tie-breaking by UUID.

- [ ] **Step 5: Run and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git add Sources/TopTimerDomain/TimerEngine.swift Tests/TopTimerDomainTests/TimerEngineTests.swift
git commit -m "feat: add deterministic multi-timer engine"
```

### Task 4: Recurrence calculation and successor uniqueness

**Files:**
- Create: `Sources/TopTimerDomain/RecurrenceCalculator.swift`
- Test: `Tests/TopTimerDomainTests/RecurrenceCalculatorTests.swift`

- [ ] **Step 1: Write failing recurrence tests**

```swift
func testWeekdayRuleSkipsWeekend() throws {
    let friday = date("2026-09-04T15:00:00+03:00")
    let next = try calculator.nextDate(after: friday, rule: .weekdays(hour: 9, minute: 0))
    XCTAssertEqual(next, date("2026-09-07T09:00:00+03:00"))
}

func testCompletionCreatesOnlyOneSuccessor() throws {
    let result1 = try recurrence.complete(timer, at: dueDate)
    let result2 = try recurrence.complete(result1.completed, at: dueDate)
    XCTAssertNotNil(result1.successor)
    XCTAssertNil(result2.successor)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter RecurrenceCalculatorTests`
Expected: compilation fails because recurrence services are missing.

- [ ] **Step 3: Implement bounded calendar search**

Use `Calendar.nextDate(after:matching:matchingPolicy:repeatedTimePolicy:direction:)`
with `.nextTime` and `.first`. Fixed intervals must be within 1 second and 365
days. Calendar search must stop after 370 candidate days and throw if no date is
found. Store `successorID` on the completed occurrence before returning a new
timer.

- [ ] **Step 4: Add DST and selected-weekday tests**

Use `America/New_York` fixtures for nonexistent and repeated local times. Test
daily, weekdays, weekly, selected weekdays, interval bounds, time-zone changes,
and a second completion call on the same occurrence.

- [ ] **Step 5: Run and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git add Sources/TopTimerDomain/RecurrenceCalculator.swift Tests/TopTimerDomainTests/RecurrenceCalculatorTests.swift
git commit -m "feat: add recurring timer schedules"
```

### Task 5: Core Data persistence and atomic completion

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TopTimerPersistence/CoreDataModel.swift`
- Create: `Sources/TopTimerPersistence/CoreDataStore.swift`
- Create: `Sources/TopTimerPersistence/TimerRepository.swift`
- Test: `Tests/TopTimerPersistenceTests/TimerRepositoryTests.swift`

- [ ] **Step 1: Add persistence targets and a failing in-memory test**

Add `TopTimerPersistence` and `TopTimerPersistenceTests` targets. Write:

```swift
func testCompletionAndSuccessorPersistAtomically() async throws {
    let store = try CoreDataStore.inMemory()
    let repository = CoreDataTimerRepository(store: store)
    let saved = try await repository.insert(repeatingTimer)
    let outcome = try await repository.complete(saved.id, at: dueDate)
    XCTAssertEqual(try await repository.historyCount(for: saved.id), 1)
    XCTAssertEqual(try await repository.successors(of: saved.id).count, 1)
    _ = try await repository.complete(saved.id, at: dueDate)
    XCTAssertEqual(try await repository.historyCount(for: saved.id), 1)
    XCTAssertEqual(try await repository.successors(of: saved.id).count, 1)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter TimerRepositoryTests`
Expected: compilation fails because `CoreDataStore` is missing.

- [ ] **Step 3: Implement the programmatic managed model**

Create `TimerRecord`, `HistoryRecord`, and `PresetRecord` entities in
`NSManagedObjectModel`. Make UUID identity fields nonoptional and indexed. Add a
unique constraint to timer occurrence ID and history occurrence ID. Store enums
and recurrence/tags as versioned JSON data; reject unknown schema versions.

- [ ] **Step 4: Implement actor-isolated repositories**

Expose:

```swift
public protocol TimerRepository: Sendable {
    func insert(_ timer: TimerItem) async throws -> TimerItem
    func update(_ timer: TimerItem) async throws
    func active(limit: Int) async throws -> [TimerItem]
    func complete(_ id: UUID, at date: Date) async throws -> CompletionOutcome
    func softDelete(_ id: UUID, at date: Date) async throws
}
```

Clamp every requested limit to `1...200`. In `complete`, fetch, validate, append
history, persist successor identity and successor, then save once. Roll back the
context on any error.

- [ ] **Step 5: Test relaunch, duplicate rejection, rollback, and pagination**

Use a temporary SQLite URL for relaunch recovery. Force a constraint violation
inside completion and prove neither history nor successor persists. Test 201
records return 200 and cursor pagination returns the remainder.

- [ ] **Step 6: Run and commit**

Run: `swift test`
Expected: all domain and persistence tests pass.

```bash
git add Package.swift Sources/TopTimerPersistence Tests/TopTimerPersistenceTests
git commit -m "feat: persist timers and history atomically"
```

### Task 6: History analytics, search, recovery, and CSV

**Files:**
- Create: `Sources/TopTimerDomain/HistoryAnalytics.swift`
- Create: `Sources/TopTimerDomain/CSVExporter.swift`
- Test: `Tests/TopTimerDomainTests/HistoryAnalyticsTests.swift`
- Test: `Tests/TopTimerDomainTests/CSVExporterTests.swift`
- Modify: `Sources/TopTimerPersistence/TimerRepository.swift`
- Modify: `Tests/TopTimerPersistenceTests/TimerRepositoryTests.swift`

- [ ] **Step 1: Write failing analytics and CSV tests**

```swift
func testSearchesTitleDescriptionAndTagsCaseInsensitively() {
    XCTAssertEqual(analytics.filter(entries, query: "CLIENT").map(\.id), [clientEntry.id])
}

func testCSVQuotesCommasQuotesAndNewlines() throws {
    let csv = try CSVExporter().export([entry(title: "A, \"quoted\"\nline")])
    XCTAssertTrue(csv.contains("\"A, \"\"quoted\"\"\nline\""))
    XCTAssertTrue(csv.hasPrefix("id,title,description,tags,"))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'HistoryAnalyticsTests|CSVExporterTests'`
Expected: compilation fails because both services are missing.

- [ ] **Step 3: Implement bounded analytics and RFC 4180 export**

`HistoryAnalytics` accepts at most 10,000 already-fetched entries and groups by
calendar day, week, timer, and tag. `CSVExporter` emits UTF-8 with CRLF lines and
columns `id,title,description,tags,kind,started_at,ended_at,elapsed_seconds,reason`.
Escape a field by doubling quotes and quoting when it contains comma, quote, CR,
or LF.

- [ ] **Step 4: Add repository search, editing, soft delete, and recovery**

Fetch at most 200 rows per page with date bounds and a stable
`(endedAt DESC, id DESC)` cursor. Search title, details, and decoded normalized tag
values after the date-bounded fetch. Editing preserves occurrence identity and
system timestamps. Recovery clears `deletedAt`; permanent cleanup only removes
records older than the configured retention cutoff.

- [ ] **Step 5: Run and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git add Sources/TopTimerDomain Sources/TopTimerPersistence Tests
git commit -m "feat: add timer history reports and CSV export"
```

### Task 7: Notifications, actions, and alert sounds

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TopTimerSystem/NotificationController.swift`
- Create: `Sources/TopTimerSystem/AlertSoundController.swift`
- Test: `Tests/TopTimerSystemTests/NotificationControllerTests.swift`
- Test: `Tests/TopTimerSystemTests/AlertSoundControllerTests.swift`

- [ ] **Step 1: Add system targets and write failing notification tests**

```swift
func testAuthorizedTimerSchedulesStableRequest() async throws {
    let center = RecordingNotificationCenter(status: .authorized)
    let controller = NotificationController(center: center)
    try await controller.schedule(timer)
    XCTAssertEqual(center.requests.count, 1)
    XCTAssertEqual(center.requests[0].identifier, "timer-\(timer.id.uuidString)")
    XCTAssertEqual(center.requests[0].body.count, 120)
}

func testDeniedAuthorizationDoesNotThrow() async throws {
    let center = RecordingNotificationCenter(status: .denied)
    try await NotificationController(center: center).schedule(timer)
    XCTAssertTrue(center.requests.isEmpty)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter NotificationControllerTests`
Expected: compilation fails because the controller is missing.

- [ ] **Step 3: Implement the notification boundary**

Wrap `UNUserNotificationCenter` in a `NotificationCenterClient` protocol. Register
one category with `STOP`, `REPEAT`, and `SNOOZE` actions before scheduling. Check
authorization status every time, request it only after first timer creation, cap
pending TopTimer requests at 64, and cancel the corresponding request on pause,
edit, acknowledge, or deletion. Route action payloads using timer UUID only.

- [ ] **Step 4: Test and implement sound import**

Write a failing test that rejects files over 20 MB and unsupported extensions,
then implement `AlertSoundController`. Accept `aiff`, `wav`, `caf`, and `mp3`;
copy using a generated stable filename under Application Support; play with
`NSSound`; clamp volume to `0...1`; fall back to `Glass` when loading fails.

- [ ] **Step 5: Test action routing and pending-request cap**

Prove Stop acknowledges, Repeat creates the same duration, Snooze uses the saved
bounded preference, and a 65th request removes only the oldest TopTimer request.

- [ ] **Step 6: Run and commit**

Run: `swift test`
Expected: all tests pass with zero warnings.

```bash
git add Package.swift Sources/TopTimerSystem Tests/TopTimerSystemTests
git commit -m "feat: add notifications and alert sounds"
```

### Task 8: Global shortcuts, login item, and sleep assertion

**Files:**
- Create: `Sources/TopTimerSystem/GlobalHotKeyController.swift`
- Create: `Sources/TopTimerSystem/LoginItemController.swift`
- Create: `Sources/TopTimerSystem/SleepAssertionController.swift`
- Test: `Tests/TopTimerSystemTests/GlobalHotKeyControllerTests.swift`
- Test: `Tests/TopTimerSystemTests/SleepAssertionControllerTests.swift`

- [ ] **Step 1: Write failing ownership and conflict tests**

```swift
func testSleepAssertionHasSingleOwner() throws {
    let client = RecordingPowerAssertionClient()
    let controller = SleepAssertionController(client: client)
    try controller.setRunningTimerCount(2, enabled: true)
    try controller.setRunningTimerCount(1, enabled: true)
    controller.setRunningTimerCount(0, enabled: true)
    XCTAssertEqual(client.created, 1)
    XCTAssertEqual(client.released, 1)
}

func testConflictingShortcutPreservesPreviousRegistration() throws {
    let registrar = RecordingHotKeyRegistrar(rejectKeyCode: 8)
    let controller = GlobalHotKeyController(registrar: registrar)
    try controller.register(.init(keyCode: 1, modifiers: 256), for: .quickEntry)
    XCTAssertThrowsError(try controller.register(.init(keyCode: 8, modifiers: 256), for: .quickEntry))
    XCTAssertEqual(controller.shortcut(for: .quickEntry)?.keyCode, 1)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter 'GlobalHotKeyControllerTests|SleepAssertionControllerTests'`
Expected: compilation fails because integration controllers are missing.

- [ ] **Step 3: Implement bounded adapters**

Use Carbon `RegisterEventHotKey` for exactly two commands: quick entry and
pause/resume priority timer. Register a replacement before unregistering the old
shortcut. Use `SMAppService.mainApp` for launch at login and surface
`requiresApproval`. Use one `kIOPMAssertionTypePreventUserIdleSystemSleep`
assertion, releasing it when count reaches zero and in `deinit`.

- [ ] **Step 4: Add failure-path tests**

Prove failed IOKit creation leaves no owned ID, repeated release is harmless,
negative timer count is rejected, and login-item errors map to user-readable
status without being swallowed.

- [ ] **Step 5: Run and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git add Sources/TopTimerSystem Tests/TopTimerSystemTests
git commit -m "feat: add macOS timer integrations"
```

### Task 9: App state, orchestration, and suggestions

**Files:**
- Modify: `Package.swift`
- Create: `Sources/TopTimerApp/AppState.swift`
- Test: `Tests/TopTimerAppTests/AppStateTests.swift`

- [ ] **Step 1: Add app targets and a failing creation-flow test**

```swift
@MainActor
func testCreatePersistsBeforeSchedulingAndPublishing() async throws {
    let recorder = OperationRecorder()
    let state = AppState(
        repository: RecordingTimerRepository(recorder: recorder),
        notifications: RecordingNotifications(recorder: recorder),
        parser: TimerParser(calendar: utcCalendar, now: fixedNow)
    )
    try await state.create(command: "25m Review #client")
    XCTAssertEqual(recorder.operations, ["persist", "schedule", "publish"])
    XCTAssertEqual(state.timers.first?.title, "Review")
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AppStateTests`
Expected: compilation fails because `AppState` is missing.

- [ ] **Step 3: Implement `@MainActor AppState`**

Publish timers, quick-entry text, inline error, notification status, preferences,
suggestions, selected editor timer, and bounded history pages. Creation must
persist, schedule, then publish. State transitions update persistence before
external effects. A one-second UI timer only calls `refresh(now:)`; it never
changes domain remaining time.

- [ ] **Step 4: Implement suggestions and preset counters**

Return at most 20 entries ranked by exact tag prefix, use count, and last-used
date. Persist only successful commands. Deleting history does not delete a saved
preset. Add tests for cap, ranking, deduplication, and failed-command exclusion.

- [ ] **Step 5: Test notification actions and relaunch recovery**

Drive Stop, Repeat, and Snooze through `AppState`, then initialize a second state
from the same repository and prove active timers and completed items recover.

- [ ] **Step 6: Run and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git add Package.swift Sources/TopTimerApp/AppState.swift Tests/TopTimerAppTests
git commit -m "feat: orchestrate timer application state"
```

### Task 10: Menu-bar shell, quick entry, list, and editor

**Files:**
- Create: `Sources/TopTimerApp/TopTimerApp.swift`
- Create: `Sources/TopTimerApp/StatusBarController.swift`
- Create: `Sources/TopTimerApp/QuickEntryView.swift`
- Create: `Sources/TopTimerApp/TimerListView.swift`
- Create: `Sources/TopTimerApp/TimerEditorView.swift`
- Test: `Tests/TopTimerAppTests/StatusFormattingTests.swift`

- [ ] **Step 1: Write failing menu-bar formatting tests**

```swift
func testMenuBarUsesPriorityTimerAndTabularFormat() throws {
    let title = StatusTitleFormatter().title(
        for: [laterTimer, soonerTimer],
        at: fixedNow,
        format: .compact,
        showsIcon: true
    )
    XCTAssertEqual(title, "◴ 14:38")
}

func testIdleMenuBarShowsOnlyMark() {
    XCTAssertEqual(StatusTitleFormatter().title(for: [], at: fixedNow, format: .compact, showsIcon: true), "◴")
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter StatusFormattingTests`
Expected: compilation fails because the formatter is missing.

- [ ] **Step 3: Implement the app composition root and status item**

Create an `NSStatusItem`, `NSPopover`, and `NSHostingController`. Set
`NSApplication.shared.setActivationPolicy(.accessory)`. Update the status title
from `TimerPriority`, use monospaced digits, and set an accessibility label that
includes the active timer title and remaining time. Clicking toggles the popover;
the global shortcut opens it and restores the previously active app after close.

- [ ] **Step 4: Implement the approved quick-entry view**

Build the 260-point popover with the original mark, borderless focused field,
precise inline error, Return-to-create, a visible Run/Play control, Space-to-pause
when all input text is selected, keyboard suggestion list, and icon-only
settings/Run/list/quit toolbar. Return and Run use the same action; when the field
is empty they start a count-up stopwatch at `00:00`. Use system colors,
`#6F9BFF` timing accent, SF typography, 8-point outer geometry, tooltips, focus
rings, and accessibility identifiers.

- [ ] **Step 5: Implement the bounded timer list and detail editor**

Render at most 100 rows. Each row shows title, tags, remaining time, end time,
recurrence summary, progress line, and stable hover/focus controls. The editor
validates title, 500-character description, 12 tags, duration, recurrence, sound,
and volume before saving. Include duplicate, restart, pause/resume, acknowledge,
soft delete, and restore actions.

- [ ] **Step 6: Build and commit**

Run: `swift test && swift build -Xswiftc -warnings-as-errors`
Expected: all tests and debug build pass with zero warnings.

```bash
git add Sources/TopTimerApp Tests/TopTimerAppTests
git commit -m "feat: add native menu-bar timer interface"
```

### Task 11: History, reports, settings, and window coordination

**Files:**
- Create: `Sources/TopTimerApp/WindowCoordinator.swift`
- Create: `Sources/TopTimerApp/HistoryView.swift`
- Create: `Sources/TopTimerApp/ReportsView.swift`
- Create: `Sources/TopTimerApp/SettingsView.swift`
- Test: `Tests/TopTimerAppTests/SettingsValidationTests.swift`

- [ ] **Step 1: Write failing settings-boundary tests**

```swift
func testSettingsClampBoundedValues() {
    var settings = TopTimerSettings.defaults
    settings.snoozeSeconds = 0
    settings.historyPageSize = 5_000
    settings.alertVolume = 2
    settings.normalize()
    XCTAssertEqual(settings.snoozeSeconds, 60)
    XCTAssertEqual(settings.historyPageSize, 200)
    XCTAssertEqual(settings.alertVolume, 1)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SettingsValidationTests`
Expected: compilation fails because settings are missing.

- [ ] **Step 3: Implement retained native windows**

`WindowCoordinator` owns one `NSWindowController` each for timer list, history,
reports, and settings. Reopening brings the existing window forward. Closing
releases only the hosted view hierarchy, never the app state or status item.

- [ ] **Step 4: Implement history and reports**

History provides date bounds, title/description/tag search, 200-row pages, edit,
soft delete, recovery, and `NSSavePanel` CSV export. Reports use Swift Charts for
daily and weekly totals and provide timer/tag totals in accessible tables. Empty,
loading, permission, and persistence-error states each give a direct next action.

- [ ] **Step 5: Implement settings and system status**

Expose compact/clock/seconds menu formats, show-icon toggle, two hotkeys, alert,
volume, snooze, 12/24-hour display, launch at login, prevent sleep, and retention.
Failed hotkey replacement preserves the previous shortcut. Notification denial
shows an Open Notification Settings button. Imported sounds show validation
errors without losing the prior sound.

- [ ] **Step 6: Test, build, and commit**

Run: `swift test && swift build -Xswiftc -warnings-as-errors`
Expected: all tests and debug build pass with zero warnings.

```bash
git add Sources/TopTimerApp Tests/TopTimerAppTests
git commit -m "feat: add timer history reports and settings UI"
```

### Task 12: Packaging, icon, open-source handover, install, and smoke test

**Files:**
- Create: `Sources/TopTimerApp/Resources/Info.plist`
- Create: `scripts/generate-icon.swift`
- Create: `scripts/package-app.sh`
- Create: `scripts/verify-app.sh`
- Create: `README.md`
- Create: `CONTRIBUTING.md`
- Create: `docs/architecture.md`
- Modify: `docs/decisions.md`

- [ ] **Step 1: Write the failing bundle verification script**

Make `scripts/verify-app.sh` exit nonzero unless its explicit app path contains an
executable `Contents/MacOS/TopTimer`, a parseable `Contents/Info.plist`,
`LSUIElement=true`, bundle identifier `com.lelabodigital.TopTimer`, an icon, and a
valid ad-hoc code signature. It must also reject a path equal to `/`, `$HOME`, or
the repository root.

Run: `bash scripts/verify-app.sh build/TopTimer.app`
Expected: FAIL with `TopTimer.app not found`.

- [ ] **Step 2: Generate an original icon and Info.plist**

Use Core Graphics in `scripts/generate-icon.swift` to draw a midnight square with
a blue circular timing rail, amber center dot, and two white hands. Generate all
macOS icon sizes into `TopTimer.iconset` and run `iconutil -c icns`. The plist must
set `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleIconFile`,
`CFBundleShortVersionString=1.0.0`, `CFBundleVersion=1`, `LSUIElement=true`, and
`LSMinimumSystemVersion=13.5`.

- [ ] **Step 3: Implement bounded release packaging**

`scripts/package-app.sh` must resolve the repository root, require the destination
to be inside `<repo>/build`, remove only the explicit `build/TopTimer.app`, run
`swift build -c release -Xswiftc -warnings-as-errors`, assemble the standard
bundle, copy resources and icon, then run:

```bash
codesign --force --deep --sign - build/TopTimer.app
bash scripts/verify-app.sh build/TopTimer.app
```

- [ ] **Step 4: Write handover documentation**

README must document features, privacy, macOS requirement, quick syntax, build,
test, package, install, uninstall, GitHub remote setup, signing/notarization limits,
and screenshots. CONTRIBUTING must require conventional commits, tests, warning-
free builds, and decision-ledger updates. Architecture notes must map modules,
data flow, Core Data invariants, recurrence uniqueness, and failure handling.

- [ ] **Step 5: Run the complete automated gate**

Run:

```bash
swift test
swift build -c release -Xswiftc -warnings-as-errors
bash scripts/package-app.sh
bash scripts/verify-app.sh build/TopTimer.app
git diff --check
```

Expected: every command exits 0, all tests pass, the release build emits no
warnings, and bundle verification prints `TopTimer.app verified`.

- [ ] **Step 6: Install safely and launch**

Resolve `/Applications/TopTimer.app`. If it already exists, move only that exact
bundle to the Trash with a timestamp before installing. Then run:

```bash
ditto build/TopTimer.app /Applications/TopTimer.app
open -a /Applications/TopTimer.app
pgrep -fl '/Applications/TopTimer.app/Contents/MacOS/TopTimer'
```

Expected: `pgrep` prints exactly one installed TopTimer process.

- [ ] **Step 7: Perform human-flow and visual verification**

Inspect the rendered popover in both appearances and verify: first-run
notification state, `15m Tea #home`, description editing, two simultaneous timers,
priority menu title, pause/resume, stopwatch, completion notification, Stop,
Repeat, Snooze, one recurring successor, quit/relaunch recovery, history search,
soft-delete recovery, CSV export, shortcut conflict, launch-at-login status, and
sleep-prevention release. Capture a screenshot for the README only after checking
it contains no private timer text.

- [ ] **Step 8: Commit the verified release**

```bash
git add LICENSE Sources scripts README.md CONTRIBUTING.md docs Package.swift
git commit -m "chore: package TopTimer 1.0.0"
git status --short --branch
git log --oneline --decorate -12
```

Expected: clean `main`, no remote configured, and conventional commits for every
green milestone. Do not push, publish, notarize, or create a GitHub repository.

## Final requirement trace

- Natural language, stopwatches, tags, descriptions, and suggestions: Tasks 1–2,
  9–10.
- Accurate multi-timer state and menu-bar priority: Tasks 3, 9–10.
- Per-timer recurrence and duplicate prevention: Tasks 4–5, 10.
- Notifications, actions, custom sound, and volume: Task 7.
- History, editing, recovery, reports, charts, and CSV: Tasks 5–6, 11.
- Shortcuts, launch at login, and prevent sleep: Tasks 8 and 11.
- Original reduced native UI and accessibility: Tasks 10–11.
- Offline privacy, open-source handover, Git, package, install, and launch: Task 12.
