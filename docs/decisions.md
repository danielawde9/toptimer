# Decisions ledger

This ledger is append-only. Later changes supersede earlier entries rather than
rewriting history.

## 2026-09-04 — Native macOS implementation

**Decision:** Build TopTimer with SwiftUI and small AppKit integration points,
targeting macOS 13.5 and later.

**Why:** A native implementation provides the smallest installed footprint and
the most reliable access to menu-bar, notification, login-item, keyboard
shortcut, and power-management APIs.

**If the client answers differently:** A cross-platform requirement would need a
new architecture decision and separate Windows/Linux interface designs.

## 2026-09-04 — Original identity with functional parity

**Decision:** Match the publicly documented timer capabilities and efficient
workflow of Horo without using its name, source, icon, artwork, or pixel-for-pixel
interface. The product name is TopTimer.

**Why:** The requested functionality is useful, while an original identity keeps
the open-source project maintainable and avoids confusing it with the existing
commercial product.

**If the client answers differently:** Supplied, licensed brand assets can replace
TopTimer assets after their rights and permitted uses are documented.

## 2026-09-04 — Local-only data

**Decision:** Store timers, presets, settings, and history locally with Core Data.
The app has no account, analytics, telemetry, or network feature.

**Why:** Timer data does not require a service, and local-only storage preserves
privacy and offline reliability.

**If the client answers differently:** Sync would require a separate privacy,
conflict-resolution, and service-availability design.

## 2026-09-04 — Free open-source release

**Decision:** Ship all implemented features without a paid tier under the MIT
license.

**Why:** The client requested an open-source repository and will connect the local
Git repository to GitHub later.

**If the client answers differently:** A license change must happen before public
distribution and may require contributor consent after outside contributions.

## 2026-09-04 — Recurrence and menu-bar priority

**Decision:** Recurrence is chosen per timer: none, interval, daily, weekdays,
weekly, or selected weekdays. With multiple active countdowns, the menu bar shows
the one due soonest; clicking it reveals every timer and stopwatch.

**Why:** This keeps the menu bar compact while preserving direct access to all
running work. Explicit recurrence prevents accidental repeating alerts.

**If the client answers differently:** Menu-bar selection can become a configurable
preference, and additional recurrence rules can be added without changing saved
timer identity.

## 2026-09-04 — Timer metadata

**Decision:** Each timer and stopwatch has a short title, an optional description
of up to 500 characters, and up to 12 tags of 32 characters each. Title and tags
can be entered in the quick command; descriptions use the expanded editor.

**Why:** The client wants users to record what a timer is for and organize timers
without making fast creation cumbersome. Explicit limits keep storage, search,
notifications, and exports predictable.

**If the client answers differently:** The limits can be raised with matching UI,
storage, notification truncation, and export tests.

## 2026-09-04 — Wall-clock DST parsing

**Decision:** Nonexistent local wall-clock times entered with `@` advance to the
next valid local time (for example, 2:30 during the spring-forward gap becomes
3:00). Repeated local times prefer the first occurrence that is still later than
now.

**Why:** This gives users a predictable next alarm and keeps wall-clock parsing
aligned with the recurrence scheduler's forward, next-occurrence behavior.

**If the client answers differently:** Rejecting nonexistent times would require
a validation error and UI correction; advancing to the next day would change the
alarm's date; preferring the second repeated occurrence would change the fold
selection and elapsed duration.

## 2026-09-04 — Running recurrence successors

**Decision:** Completing a recurring countdown immediately creates one distinct,
running successor whose absolute deadline is the next recurrence occurrence.

**Why:** The next occurrence can be scheduled and recovered without waiting for
the user to start it, while preserving the original duration and metadata.

**If the client answers differently:** Successors could instead be persisted as
idle drafts, but scheduling and menu-bar behavior would need an explicit start
action for every occurrence.

## 2026-09-04 — Scheduled-window successor duration

**Decision:** A running successor's countdown duration equals the elapsed window
from completion to its next scheduled deadline. The recurrence rule remains
unchanged so later completions continue using the configured schedule.

**Why:** Pause, resume, restart, and persisted timer invariants remain coherent
even when a calendar recurrence is many hours or days away.

**If the client answers differently:** A pre-alert window could use the original
duration, but it would need a separate scheduled-deadline field and explicit UI
semantics for the interval before that alert.

## 2026-09-04 — Clarification superseding original-duration wording

This clarification supersedes only the sentence in **Running recurrence
successors** that said the original numeric duration is preserved. Title,
description, tags, recurrence, and sound metadata are preserved. For calendar
schedules, active duration is the completion-to-next-deadline window; for fixed
intervals, it is the interval. This prevents invalid pause, progress, and
restart state. If pre-alert semantics are desired, add a separate template or
pre-alert field and corresponding UI.

## 2026-09-04 — Empty-input Run action

**Decision:** Return and the visible Run/Play control share one creation action.
With timer input, the action starts a countdown; with an empty field, it starts a
stopwatch at `00:00` that counts upward.

**Why:** The client explicitly expects pressing Run with no configured duration to
start count-up timing. One shared action keeps mouse and keyboard behavior
consistent.

**If the client answers differently:** A separate stopwatch control could be
added, but it would make the compact popover denser and split equivalent creation
behavior across two actions.

## 2026-09-05 — Persistence payload version one

**Decision:** Persist timer and history payloads in a version-one JSON envelope;
selected recurrence weekdays are sorted before storage.

**Why:** A version gate makes incompatible future schemas fail loudly, and sorted
weekday values make the otherwise unordered set stable for backups and tests.

**If the client answers differently:** A requested migration policy would add a
new decoder/migration path while retaining the existing version-one reader.

## 2026-09-05 — Canonical persistence timestamps

**Decision:** Encode version-one persistence dates as Unix milliseconds and data
as Base64, with sorted JSON object keys at both envelope and payload layers.

**Why:** Explicit representations make backups byte-stable across independent
encoder instances and eliminate reliance on Foundation's default date strategy.

**If the client answers differently:** A different interchange format requires a
new envelope version and a migration reader for existing local records.

## 2026-09-05 — Canonical payload version two

**Decision:** Emit canonical payloads as envelope version two while retaining a
read-only version-one decoder using its original Foundation date semantics.

**Why:** The completed version-one implementation may already have local data;
changing its timestamp codec without a version boundary would make that data
unreadable.

**If the client answers differently:** Dropping version-one compatibility is a
data-retention decision and would require an explicit migration or reset flow.
