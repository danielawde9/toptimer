# Task 10 fix round 4

Status: implemented and verified from base `62b4e45`, pending independent review.

## Delivered

- Editor now renders duration and every recurrence mode, completion interval,
  local hour/minute, weekly weekday, and seven selected-weekday toggles. Inputs
  bind to EditorDraft; invalid calendar ranges and invalid numeric text produce
  precise inline errors. Invalid input remains editable and cannot silently save
  an older numeric value. Sound choices remain selected and visibly unavailable
  when absent from the current catalog.
- SoundCatalog supplies 14 standard macOS built-in names and enumerates imported
  stable file basenames in Application Support/TopTimer/Sounds. The catalog caps
  at 100 entries and enumerates at most 200 direct children; symbolic links and
  unsupported files are excluded. The installed `/System/Library/Sounds` names
  were checked in this session and match the built-in list. StatusBarController
  owns the catalog state and passes it through to the editor. Load failure keeps
  the prior catalog, displays an error, and offers Retry.
- TimerRowTiming derives countdown remaining and stopwatch elapsed time from
  domain methods, including paused/completed states; the rendered Text uses
  monospaced digits. Rows retain end-time and recurrence summaries, tags, and a
  two-point progress line. A single native Actions menu reserves 60 points and
  stays mounted at low opacity outside hover/focus; native keyboard focus does
  not change its frame. Actions are state-specific and remain available through
  the menu and accessibility tree.
- Quick-entry toolbar has exactly Settings, Run, List, Quit; each image label
  itself provides a 28-point pointer target, tooltip and accessibility label.
  The popover returns to the specified 260-point width.
- Recently Deleted is a visible second collection, with at most 100 rows and
  Restore. The real Core Data query has a hard fetch limit of 100 and deterministic
  ordering. AppState publishes only after persistence. Restore uses the existing
  transaction/revision increment; stale metadata snapshots cannot overwrite it.
  Restored running countdowns reschedule their durable deadline.

## RED evidence

All commands ran in the specified TopTimer worktree on 2026-09-07.

- `swift test --filter Task10Round4Tests`: initial compilation RED after fixing
  a test-factory argument identified missing TimerRowTiming, deleted query, and
  AppState.deletedTimers. After adding those minimal surfaces, 4 tests ran with
  5 expected failures: invalid hour, weekly weekday, selected weekdays were
  accepted; sound list returned 150 instead of 100 and one built-in instead of
  multiple (16:30 session log).
- `swift test --filter Task10RenderedTests`: real NSHostingView/native controls
  showed 3 instead of 6 editor text fields, 2 instead of 4 pickers, 6 instead of
  4 toolbar buttons, and native pointer targets between 11 and 16.5 points
  instead of 28 (16:31). Initial AX-only harness returned no accessibility
  children in the test runner, so the harness was corrected to traverse native
  NSView descendants before treating those native-control failures as RED.
- Row-menu test RED: zero mounted menu controls outside hover; expected one
  (16:34). The first menu implementation still had a 25-point intrinsic image
  menu; native Actions text supplies a usable fixed reserved area (16:38 GREEN).
- Catalog-state test RED: SoundCatalogState was absent (16:37), then GREEN with
  imported identity selection and retained prior catalog after a throwing load.
- Native duration-edit test RED: entering `abc` left validation nil; a second
  RED showed numeric-prefix text `12oops` was accepted (16:38 and 16:41). The
  field now preserves raw text and requires complete numeric parsing.
- Restored-running notification test RED: observed `[schedule, cancel]`, expected
  `[schedule, cancel, schedule]` (16:44). Scheduling now follows durable restore.

Additional integration coverage exercises real imported filesystem identities,
link exclusion, seven rendered weekday choices, actual native Restore clicks,
native first-responder geometry, real Core Data bounds and stale-write rejection.
No prior tests were removed or weakened. Protocol fakes only gained the newly
required deleted query method.

## Final GREEN evidence

- Focused tests: `swift test --filter 'Task10RenderedTests|Task10Round4Tests'` —
  13 tests, zero failures (16:44:42).
- Full `swift test` — 207 tests, zero failures (16:45:00); captured in
  `.build/task10-round4-full-tests.log`.
- `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  — succeeded, zero warnings.
- `swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  — succeeded, zero warnings.
- `git diff --check` — clean.
- Modified UI and new tests were formatted with the Xcode swift-format binary.

## Visual evidence and limits

Rendered the actual production SwiftUI views in NSHostingView, exported bitmap
proof with a light/dark native background, and inspected the images. Light proof
is under `.build/task10-round4-light`; dark proof is under
`.build/task10-round4-dark`. Checked weekly editor, selected weekdays, remaining
time row, Recently Deleted/Restore, and four-button quick toolbar. The host's
large empty margins are the test window, not a new product layout.

The test runner exposes native controls but returns an empty SwiftUI AX child
tree. Keyboard first-responder acceptance and stable native frames are tested;
an end-to-end VoiceOver speech/rotor session is not claimed. No packaged-app
launch, import-file picker flow, or audible notification playback was performed
in this UI repair round. The existing separate system sound-import implementation
is consumed through its stable stored file identities; future task work still
owns any broader preferences/import workflow.

## Files

- Sources/TopTimerApp: AppState, QuickEntryView, StatusBarController,
  TimerEditorView, TimerListView; new SoundCatalog and TimerRowTiming.
- Sources/TopTimerPersistence/TimerRepository.swift: capped deleted query.
- Tests/TopTimerAppTests: new Task10RenderedTests and Task10Round4Tests;
  AppStateTests protocol fake addition.
- Tests/TopTimerPersistenceTests/TimerRepositoryTests.swift: protocol fake addition.
- docs/decisions.md: appended explicit editor/recovery/catalog defaults.
- docs/lessons.md: recurring rendered-boundary failure and executable detectors.

No push, deployment, or unrelated project changes.
