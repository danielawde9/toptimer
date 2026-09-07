# Task 11 fix round 2

Status: implemented and verified from 5dac351; no push. Prior untracked
SettingsStore.swift and SettingsStoreTests.swift were preserved, extended, and
verified before inclusion.

## Root causes

The UI controls did not form a complete persistence-to-runtime chain. Settings
were transient; the prior draft codec omitted both shortcuts. History and
Reports shared historyPage, historyLoading, and inlineError, so one window
replaced or blocked the other. Mutation refreshes discarded filters. Date-only
Through forwarded a time within the day. Deleted rows existed in Core Data but
had no query for discovery after relaunch. Reports and exports used only the
loaded page. closeAll iterated storage which close delegates mutate.

Systematic debugging and root-cause tracing identified these ownership and
adapter breaks before implementation. The new-timer default sound fix initially
used reconfigure; the real-engine test exposed its revision increment rejecting
new insertion. Defaults now enter the domain factory directly.

## Implemented behavior

- A bounded version-1 settings envelope persists all preferences including both
  shortcuts. Unknown versions, malformed/oversized payloads, unsafe sound names,
  and partial shortcuts fail closed. Numeric values normalize. Startup loads the
  envelope before composing AppState and controllers. Failed preference writes
  preserve the previous runtime and saved values in the tested storage boundary.
- Default alert/volume reach new timer factories. Twelve-hour mode requires
  explicit am/pm; status clock, row end time, and history use the preference.
  Snooze uses its normalized preference and preserves the source sound/volume.
  Status format/icon, both hotkeys, login, sleep prevention, and retention are
  wired. System-setting failures retain previous runtime choices and carry
  operation-specific errors; failed compensation is visible.
- Sleep assertions track the repository-selected running timer and release when
  none runs, when disabled, and at application shutdown. Sleep errors offer a
  concrete Retry. Finite retention purges at load/change/daily, capped at 10,000
  records per invocation, with a Retry action for remaining work.
- Independent History and Reports filters, requests, loading flags, errors, and
  results prevent shared-window corruption. Latest request wins. Cancel
  invalidates publication; report pagination also checks request identity before
  subsequent fetches. Mutation refreshes keep both active filters. History is a
  bounded current page with Next page; no 200-row accumulation dead end.
- Through uses the next calendar day exclusive, bridged to the existing inclusive
  repository API via Date.nextDown. DST tests prove 23- and 25-hour ranges; a real
  Core Data boundary test includes the final millisecond and excludes midnight.
- Bounded deletedHistory repository query discovers 200 durable tombstones.
  A real SQLite close/reopen/recover test proves discovery and restoration.
- Reports aggregate all selected rows using bounded pagination, rejecting ranges
  over 10,000 rows without replacing the prior report. ReportSummary computes
  validated daily, weekly, timer, and tag totals once. Two semantic SwiftUI Tables
  render native NSTableViews. Charts specify calendar units and visible titles;
  the runtime chart warning found during rendering was removed.
- CSV reads the active History query across pages and reports export-specific
  write/query failures without reloading, clearing filters, or losing the page.
  Empty/loading/error states have real actions. Notification settings deep-link
  success/failure is testable; failure names the manual System Settings path.
  Imported-sound failure preserves the active sound, including concurrent changes.
- closeAll snapshots controllers and clears ownership before calling close.
  A four-real-window regression verifies each window and hosted hierarchy closes.

## TDD and verification evidence

Observed RED then GREEN for missing shortcut round-trip persistence; absent
date-range/report APIs; deleted-history relaunch discovery; missing settings
save/runtime initialization seam; absent clock preference and notification link
seams; stale report metadata following History edit; lost notification-action
sound/volume; missing report-summary model; unsafe sound/partial shortcut decode.
Additional behavior regressions exercise full-range/cap, deterministic concurrent
consumers and cancel, sleep failure/retry, hotkey/login failure, retention, CSV
failure isolation, and real calendar query boundaries. These supplement, rather
than replace, the earlier focused RED/GREEN cases.

Final commands in this session:

- swift test: 251 tests, 0 failures.
- swift build -Xswiftc -warnings-as-errors: passed.
- swift build -c release -Xswiftc -warnings-as-errors: passed.
- git diff --check: passed.
- TOPTIMER_TASK11_PROOF=/tmp/toptimer-task11-proof swift test --filter
  Task11RenderedTests: 2 tests passed; native History table, two report tables,
  and bounded settings pickers verified.

Rendered screenshots inspected at /tmp/toptimer-task11-proof/history.png,
reports.png, and settings.png. The final light-appearance report shows both
labelled calendar charts and timer/tag totals. The settings permission-recovery
button is visually present. SwiftUI virtual button labels were not exposed by
the headless in-process AX traversal; tests assert the callable deep-link model
and native table controls rather than claiming a VoiceOver end-to-end proof.

## Rulings and remaining acceptance limits

docs/decisions.md explicitly supersedes the initial Task 11 partial-page and
in-session recovery defaults. docs/lessons.md names the executable detectors.
All report/export requests have a hard cap and fail visibly above it; History
retains one bounded page, and deleted discovery retains the latest 200 rows.
No packaging, installation, real login permission mutation, audible playback,
or full VoiceOver navigation was claimed. Those belong to packaged app acceptance.
No external messages, push, or deployment occurred.
