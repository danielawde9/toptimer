# Task 10 final quality fix

## Root causes and implementation

SwiftUI buttons, text changes, editor submission/dismissal, hotkeys, periodic
refresh, and startup/retry launched unowned Tasks. Closing the store did not wait
for them. AppOperationOwner now reserves one of at most 128 slots synchronously
before creating a main-actor task, rejects closed/full admission, skips queued jobs
after shutdown, and removes every completed job in defer. Cancellation plus an
await of every registered task is the barrier. TopTimerApplication closes admission
before tearing down UI, awaits drainage, and only then takes/closes its store.
Startup is included in that owner, so a store opened during a concurrent Quit is
also captured after drainage. Retry startup shares the owned store and concurrent
startup is guarded. Close/retry-close has a single retained task and completion
cleanup. Quick Entry snapshots its submitted command before asynchronous execution.

The source audit covered every Task and async state call in Sources/TopTimerApp.
Only the operation owner's task factory and the retained termination/retry-close
tasks remain; editor operations receive the production AppState owner explicitly.
The editor's default owner supports standalone editor hosts without an AppState.

Acknowledgement intentionally sets deletedAt, but that is archival, not a user
deletion. The bounded Core Data deleted predicate now excludes acknowledged state.
The repository restore boundary independently rejects acknowledged rows with
invalidRestore, before changing any payload or revision.

## RED/GREEN evidence

- New OperationOwnerTests initially failed to compile because the ownership API
  did not exist (`.build/final-owner-red.log`). Minimal implementation made both
  initial tests pass. This initial RED was an absent-API failure, not a runtime
  assertion failure.
- A deterministic queued-after-stop test then failed at runtime with "queued work
  started after admission closed" (`final-queued-red.log`). Checking admission
  again at execution fixed it.
- The drainage test uses a continuation and cancellation-handler handshake, with
  no sleeps. Removing the await/drain while retaining cancellation caused its
  close-before-drain assertion to fail (`final-barrier-red.log`). Restoring the
  await made it pass. This was deliberate fault-injection after initial GREEN,
  and proves that cancellation alone cannot satisfy the regression detector.
- Real Core Data acknowledged recovery test failed three assertions before the
  persistence change: row included in deleted results, Restore accepted, saved
  payload/revision changed (`final-ack-red.log`). The predicate plus independent
  restore guard makes all pass, with the exact invalidRestore error asserted.
- Additional real AppState/Core Data integration proves a suspended UI operation
  can finish actual persistence before close even after cancellation, while new
  UI work is rejected. Capacity is reserved synchronously, rejected at the bound,
  and released after normal completion. Four owner tests pass.

## Final verification

2026-09-07, on this worktree:

- `swift test`: 224 tests, zero failures (`.build/final-full.log`).
- `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`:
  successful (`.build/final-debug.log`).
- `swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`:
  successful (`.build/final-release.log`).
- `git diff --check`: clean.

## Files and concerns

Added AppOperationOwner and OperationOwnerTests. Updated AppState, QuickEntryView,
TimerListView, TimerEditorView, StatusBarController, TopTimerApplication,
TimerRepository and its real integration tests. Appended decisions, lessons, and
progress. No push, dependencies, schema changes, or unrelated feature changes.

Drainage deliberately waits for already-running platform/persistence work rather
than closing underneath it; an unresolved OS authorization request can therefore
delay Quit. Forced process termination is outside a normal-quit barrier. Existing
native rendered tests passed, but this round does not claim a packaged manual
Quit/VoiceOver smoke test. Independent review is still required.
