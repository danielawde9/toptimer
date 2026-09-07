# Interface regression lessons

## 2026-09-07 — Validate the rendered boundary

Draft properties and action helpers do not prove that a user can reach them.
Task 10 repeatedly lacked rendered recurrence controls, a deleted collection,
and a usable sound catalog despite having model methods. The executable
detectors are Task10RenderedTests (native control counts, pointer bounds, field
edits, focus geometry, and clicking Restore) and Task10Round4Tests (domain
validation, bounded real Core Data queries, stale revision rejection, and sound
catalog retention). Run both when changing these surfaces.

SwiftUI numeric formatter conversion can retain an old numeric value when text
is invalid and can accept a numeric prefix followed by junk. EditorNumberField
keeps raw input, parses the entire number, invalidates the draft on failure, and
relies on EditorDraft plus domain validation as independent guards. Native-field
tests enter both abc and 12oops to detect regression.

## 2026-09-07 — Adapter and repository parity

Controller-only tests had validated an opt-in authorization flag while the real
AppState adapter always used its false default. A typed creation boundary now
expresses the permission intent after persistence. Likewise, notification sound
identity must survive every adapter and resolve to a platform-searchable file;
storing an alert name in TimerItem is not playback proof.

Repository state gates must replay the allowed domain operation and compare the
entire result under revision CAS. A blanket active-state gate incorrectly blocked
acknowledgement and terminal metadata. Acknowledgement uses deletedAt as its
archive timestamp, so it must be distinguished from unrelated soft deletion.

Task10Round5BoundaryTests, NotificationSoundBoundaryTests, and the terminal
TimerRepositoryTests are executable regression detectors spanning the real
AppState/controller, real Core Data, native command coordinator, audio-file
conversion and actual UNMutableNotificationContent boundaries.

## 2026-09-07 — Own asynchronous work before launching it

An untracked UI Task can outlive the view and enter Core Data after normal Quit
closes its store. Register synchronously with the shared bounded operation owner;
close admission before cancelling and draining, and only then close storage.
Cancellation is a request, not evidence of completion. OperationOwnerTests includes
a deterministic cancellation-handshake detector, queued-work rejection, bounded
admission/cleanup, and real AppState/Core Data persistence-before-close coverage.

Archive timestamps do not establish deletion provenance. The acknowledged-row
repository test proves both recovery-query exclusion and restore rejection with
unchanged persisted content; do not derive recoverability from deletedAt alone.

## 2026-09-07 — Query and preference ownership must reach production

History and Reports cannot share a page or loading guard: independent windows
issue independent requests. Retain each filter, assign request identities before
awaiting, check them before publication, and invalidate them on Cancel. A report
must consume all pages within its declared hard cap or fail explicitly. Window
shutdown snapshots and clears ownership before close delegates mutate it.

Preference controls are not implementation proof. Trace every value through
startup decoding, validated save, runtime controller, and relaunch. New timer
defaults belong in the factory, not reconfigure (which increments the revision
and makes a newly inserted timer invalid). Notification action factories must
preserve sound identity and volume. Date-only bounds use calendar day boundaries,
never 86,400-second assumptions.

Executable detectors: SettingsStoreTests, Task11BehaviorTests, and
Task11RenderedTests cover these boundaries, including real SQLite reopen,
native history/report tables, four-window close, deterministic concurrent
requests, CSV failure isolation, DST days, and report capacity rejection.

## 2026-09-07 — Recovery must synchronize presentation and state

An empty-state action must update its visible controls as well as its repository
query. Task11Round3Tests follows Show all through control state, applied query,
edit/delete/recover, and export. Startup recovery keeps strict decoding but offers
safe defaults and a concrete save retry instead of repeating an unchanged error.
The rendered settings detector checks a 700 by 520 host with simultaneous errors,
its bounded fitting size, document overflow, and successful scrolling to the end.
