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
