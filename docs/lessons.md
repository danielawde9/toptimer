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
