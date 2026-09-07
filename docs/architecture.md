# TopTimer architecture

TopTimer is a Swift Package whose executable is assembled into a standard macOS
application bundle. SwiftUI owns views; small AppKit adapters own the menu-bar item,
retained windows, lifecycle, and integrations unavailable in pure SwiftUI.

## Modules

- `TopTimerDomain`: bounded timer and history values, parsing, formatting, state
  transitions, recurrence rules, priority selection, and protocol boundaries. It
  does not depend on SwiftUI, Core Data, or an implicit wall clock.
- `TopTimerPersistence`: the Core Data model, versioned payload codecs, timer and
  preset repositories, migration, bounded history/tombstone queries, and atomic
  recurrence completion.
- `TopTimerSystem`: notification authorization/scheduling/action routing, built-in
  and imported sounds, global hotkeys, launch-at-login state, and one bounded sleep
  assertion.
- `TopTimerApp`: application state, operation ownership, lifecycle, menu-bar and
  quick-entry UI, editor/list, history, reports, settings, and retained windows.
- `TopTimerExecutable`: the minimal `NSApplication` entry point and delegate wiring.

## Data flow

Quick entry is parsed and validated against the injected clock. A valid timer is
persisted before notification scheduling is attempted, then the saved repository
snapshot is published to the UI. Notification denial or scheduling failure is
visible but cannot roll back or stop a timer. Invalid input remains editable.

Running countdowns store an absolute deadline; paused countdowns store exact
remaining duration. One-second UI refreshes calculate display values and do not
mutate duration, preventing drift after sleep or process suspension. Stopwatches
derive elapsed time from their stored start/resume state.

Completion atomically transitions the occurrence, appends its single history
record, and records any successor identity. Only after that durable operation does
the app schedule the successor and deliver local sound/notification feedback.

## Core Data invariants

Versioned canonical payload envelopes fail loudly on unknown or invalid data while
retaining the supported legacy reader. Countdown duration is positive and bounded;
titles, descriptions, and tags obey domain limits. Repository updates use revision
checks and cannot overwrite occurrence lineage or terminal completion state with a
stale snapshot. History uses one completion per occurrence, soft deletion, bounded
pages of 200, and report/export aggregation capped at 10,000 records.

Acknowledgement is terminal archival and is not recoverable as a user deletion.
Actual deleted timers and history tombstones have bounded recovery paths. Store
closure begins only after the bounded application-operation owner stops admission,
cancels work, and drains its owned operations.

## Recurrence uniqueness

Recurrence is configured per countdown. Completion and successor creation share one
repository transaction. The predecessor stores the generated successor identity,
and an existing identity is returned instead of creating another row. This makes
replayed completion, relaunch recovery, and notification retries produce at most one
successor. Calendar recurrence uses local calendar arithmetic: nonexistent times
advance to the next valid local time and repeated times choose the first future
occurrence.

## Failure handling

- Persistence failure leaves the user's draft or prior published state intact and
  prevents scheduling for unsaved data.
- Invalid settings recover to normalized defaults with a visible save/acknowledge
  path; failed compensation does not pretend the platform and saved state agree.
- Notification denial remains nonblocking and links to macOS settings; malformed or
  foreign actions are rejected.
- Sound import validates a bounded regular file without following links. Preparation
  or playback failure uses the built-in fallback and surfaces a local status without
  logging timer content.
- Hotkey replacement registers first, so conflicts preserve the previous shortcut.
- The app owns at most one sleep assertion and releases it when the last timer stops
  and during shutdown.
- History/report requests use independent identities; stale async results cannot
  replace a newer filter. Pagination, retention, CSV, notifications, suggestions,
  sound files, visible timer rows, and outstanding operations all have explicit caps.

## Packaging boundary

`scripts/package-app.sh` performs a strict release build, generates original icon
art with Core Graphics, assembles only `build/TopTimer.app`, ad-hoc signs it, and
calls `scripts/verify-app.sh`. The verifier checks the executable, property list,
agent-app identity, icon, and signature. Developer ID signing, notarization,
publishing, and deployment remain owner-controlled release work.
