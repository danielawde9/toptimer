# Decisions ledger

This ledger is append-only. Later changes supersede earlier entries rather than
rewriting history.

## 2026-09-07 — Editor schedule edits

**Decision:** Editing a running countdown replaces its deadline with a new full
duration from the edit time. Idle and paused countdowns retain their state with
the new full duration; terminal timers may change metadata and alert settings
but cannot change their finished schedule.

**Why:** This keeps a visible edit deterministic without silently reviving a
completed occurrence or preserving a stale deadline after its duration changed.

**If the client answers differently:** Supporting terminal schedule changes
would require an explicit clone/restart action so history and occurrence links
remain truthful.

## 2026-09-07 — Menu-bar presentation shell

**Decision:** TopTimer runs as an accessory application with a left-aligned,
280-point quick-entry popover that expands to a 340-point direct timer list.
The sole accent is the live tabular timer value; controls use semantic macOS
colors and SF Symbols, with no custom artwork, cards, gradients, or badges.

**Why:** This preserves fast timer entry while keeping the menu-bar utility
quiet, legible, original, and recognizably native.

**If the client answers differently:** A branded visual system or broader
settings/history surface should be designed as a separate UI task rather than
added to the compact popover.

## 2026-09-07 — App-state creation durability

**Decision:** AppState parses each quick-entry submission against the clock at
submission time, persists a running timer before attempting notification
scheduling, and only then refreshes its published active-timer snapshot. A
notification authorization refusal or scheduling error never rolls back the
stored timer; instead it is surfaced as recoverable notification status/error.
The persisted repository is therefore the source of truth after a scheduling
failure.

**Why:** A local timer must continue to work if macOS notification permission is
denied or the notification center is temporarily unavailable. This ordering also
prevents a UI entry from claiming success before durable storage succeeds.

**If the client answers differently:** Treating notification delivery as a
hard requirement would require a transactional outbox or an explicit delete
rollback action, plus a recovery screen for timers whose alerts could not be
scheduled.

## 2026-09-07 — Bounded system integrations

**Decision:** TopTimer owns exactly two application-level global-hotkey slots:
Quick Entry and Pause/Resume Priority. A replacement registers first, so a
failed registration leaves the previous shortcut active; duplicate combinations
are rejected. Launch-at-login exposes the system state without registering on
read, and a typed error is returned for register or unregister failures. While
sleep prevention is enabled, TopTimer owns at most one prevent-idle-sleep IOKit
assertion, acquired only when at least one timer runs and released when none do.

**Why:** Fixed ownership bounds avoid untracked Carbon registrations and power
assertions, while explicit system status and errors give the later UI a safe,
recoverable path to explain macOS decisions.

**If the client answers differently:** More global commands need a new bounded
slot/identifier design and matching preferences UI; a different sleep policy
would require a user-visible setting and regression tests for its release
transitions.

## 2026-09-07 — Timer alert delivery and custom sounds

**Decision:** TopTimer schedules at most 64 notifications in its own
`TOPTIMER_TIMER` category, identifies each request as `timer-<timer UUID>`, and
offers Stop, Repeat, and Snooze actions. Permission is requested only when the
caller explicitly marks a first successful timer creation; later scheduling
checks the current authorization state without opening a system prompt. Snooze
is clamped to 60 seconds through 24 hours. Custom alert files are copied from a
regular, non-link AIFF, WAV, CAF, or MP3 file no larger than 20 MB into
Application Support/TopTimer/Sounds, and failures fall back to the system Glass
sound.

**Why:** Stable identifiers make cancellation and action routing safe, bounded
ownership prevents TopTimer from affecting other apps' notifications, and the
file limits avoid unsafe or unexpectedly expensive local imports. “Oldest” means
the earliest scheduled trigger date, with request identifier as the deterministic
tie-breaker; pending notification inspection has a 4,096-request safety cap.

**If the client answers differently:** More pending alerts, extra formats,
different snooze limits, or a different fallback sound require matching UI,
storage, and regression-test changes.

## 2026-09-07 — Notification replacement and sound-file handles

**Decision:** Rescheduling an existing timer replaces only its own pending
request; capacity eviction is calculated on unique post-add request IDs.
Over-capacity recovery removes the required oldest TopTimer requests, never
unrelated requests. Notification actions require the TopTimer category and a
valid timer UUID. Sound imports open the source once without following links,
validate and copy from that same descriptor, and create destination files
exclusively. Timer durations, including Repeat actions, are bounded to one year.

**Why:** These rules prevent replacement from evicting another timer, reject
forged notification payloads, and close path-based time-of-check/time-of-use
races during local file import.

**If the client answers differently:** Changing the duration limit or allowing
replacement to consume another timer's capacity would require domain and
notification compatibility changes; allowing links needs an explicit secure
file-provider policy.

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

## 2026-09-05 — Superseding correction: version-one date semantics

**Decision:** This supersedes the date-format sentence in **Canonical
persistence timestamps**: version one used Foundation's default
`deferredToDate` seconds since the reference date. Canonical version two uses
explicit Unix milliseconds; both reads and the V1-to-V2 schema migration retain
the original instant exactly.

**Why:** Version one was committed before canonical encoding was introduced.
Treating its reference seconds as Unix milliseconds corrupts recovered dates.

**If the client answers differently:** Removing legacy reads requires an
explicit data migration or a user-visible reset decision.

## 2026-09-05 — Stored timer transition authority

**Decision:** Repository updates reject stale snapshots and preserve occurrence,
predecessor, successor, and terminal completion state; recurring completion is
only performed through the atomic completion operation.

**Why:** A stale running screen must not erase an already-created recurrence
successor or its history entry.

**If the client answers differently:** Allowing terminal restarts through a
generic update needs a separate explicit transition API and concurrency policy.

## 2026-09-05 — Bounded history reports and CSV tag representation

**Decision:** History analytics reject more than 10,000 already-fetched entries.
Repository history pages and each cleanup pass are capped at 200 records. CSV
uses the stable RFC 4180 column order and sorts tags before joining them with
`|`; each row is UTF-8 text terminated with CRLF.

**Why:** Reports must not build unbounded in-memory collections, recovery and
retention work must have a bounded transaction, and sorted tag output makes a
given record export reproducibly.

**If the client answers differently:** Larger reports or retention batches need
cursor-driven aggregation/cleanup, and a different tag encoding needs a new
documented CSV contract for importers.

## 2026-09-05 — Normalized history tag totals and CSV report cap

**Decision:** Tag totals use a case-, diacritic-, and width-insensitive normalized
tag key, counting that key no more than once per history entry. CSV export uses
the same 10,000-entry maximum as analytics and rejects a larger input before
allocating its row collection.

**Why:** Repeated forms of the same tag should not inflate a single record's
reported time, and report generation has an explicit memory bound.

**If the client answers differently:** Display-preserving tag groups require a
separate canonical-label policy, and larger exports need a streaming API.

## 2026-09-07 — Local timer suggestions

**Decision:** Presets are version-one canonical local payloads, deduplicated by
normalized command and normalized tag set. Suggestions inspect no more than
10,000 records, return 1...20 values, and rank tag-prefix matches before use
count, last use, command key, and identifier.

**Why:** Quick-entry suggestions must survive relaunch without turning a
convenience feature into unbounded memory or nondeterministic UI state.

**If the client answers differently:** Cross-device suggestions or fuzzy command
matching need an explicit synchronization/privacy design and a new payload
version.

## 2026-09-07 — Task 10 editor and recovery defaults

**Decision:** Duration and completion interval use explicitly labelled seconds;
calendar schedules use local 24-hour hour/minute fields. Recently Deleted is a
separate collection showing the newest 100 soft-deleted timers. Restore preserves
the timer's durable state/deadline, increments its revision, and reschedules a
running countdown. A row reserves 60 points for one native Actions menu.

**Why:** These choices expose the complete domain configuration in a small native
form, keep each collection within the approved row bound, and preserve keyboard
focus without shifting row content. Numeric parse failures invalidate the draft
while retaining the entered text, so Save cannot use a stale number.

**Decision:** The sound picker combines the 14 standard macOS alert names with
imported file basenames from TopTimer/Sounds. It returns at most 100 identities
and inspects at most 200 direct filesystem children. Missing selected sounds stay
visible as unavailable; load failure retains the last catalog and offers Retry.

**If the client answers differently:** Unit-based duration entry requires a
separate explicit units control; larger deleted/sound collections require
pagination/search. Restoring as a fresh run would require a new occurrence rather
than preserving the existing deadline.

## 2026-09-07 — Task 10 notification and playback boundaries

**Decision:** Only the successfully persisted countdown-creation path requests
notification permission when undetermined. Stopwatches and failed saves never
request it. Editing an existing timer displays its immutable kind as read-only.

**Decision:** Per-timer sound and volume remain configurable. While TopTimer runs,
durable due/manual completion uses AlertSoundController with the chosen sound and
volume. The OS notification independently uses the chosen named sound; its
volume remains controlled by macOS. The editor states this distinction explicitly.
Normal notification volume is not represented as a critical-alert volume API.

**Decision:** Notification audio is staged as PCM CAF in Library/Sounds because
UserNotifications does not search TopTimer's Application Support import folder.
Staging uses the existing 20 MB no-follow/exclusive copy boundary, 1...30-second
mono/stereo audio at at most 192 kHz, 4,096-frame conversion buffers, and at most
100 TopTimer cache files after a bounded 1,000-child directory inspection. Files
are named by a hash of their stable sound identity and never overwritten. Sound
preparation failure preserves the previous persisted editor configuration.

**Why:** This connects existing UI settings to real platform operations without
claiming control of the user's OS notification volume or silently accepting an
unplayable notification sound. Exact domain replay plus revision CAS, rather
than state-only allowlisting, authorizes terminal metadata, acknowledgement,
and restart persistence.

**If the client answers differently:** Longer notification sounds require an
explicit truncation/selection policy; a larger cache requires bounded eviction
or pagination. Critical-alert volume would require a separately justified Apple
entitlement and must not be used to emulate ordinary timer-volume settings.

## 2026-09-07 — Task 10 shutdown ownership and acknowledgement recovery

**Decision:** One main-actor operation owner admits at most 128 outstanding jobs
across startup/retry, UI commands, editor work, hotkeys, and timer refresh. Admission
is synchronous and closes synchronously on Quit. Queued jobs cannot start after
closure; running jobs are cancelled and fully awaited before Core Data closes.
Busy/closing user submissions receive an inline error. Startup attempts share one
owned store, and termination/retry-close has one separately retained task.

**Why:** Cancellation alone does not stop an operation suspended in persistence or
a platform adapter. Bounded ownership plus a drain is the storage lifetime boundary.
No timeout is allowed to close the store beneath a still-running operation.

**Decision:** Acknowledgement is terminal archival, not user deletion, even though
the existing domain uses deletedAt for its archive timestamp. Recently Deleted
excludes acknowledged states in its bounded database predicate, and Restore rejects
acknowledged rows without mutation.

**If the client answers differently:** A larger operation cap requires resource
measurement; timed shutdown must leave storage open when drainage times out.
Restoring acknowledged timers would need an explicit domain restart/recovery rule,
not removal of the archive timestamp alone.

## 2026-09-07 — Task 11 bounded auxiliary windows and reporting

**Decision:** Timer list, history, reports, and settings are separate retained native
windows with at most one controller per kind. Reopening raises the existing controller;
closing removes only that window's hosted SwiftUI hierarchy. History and report screens
request repository pages capped at 200 rows, and CSV export is limited to the currently
loaded bounded result. Recently deleted history is retained as a bounded in-session
recovery list after a successful soft delete.

**Why:** This keeps storage and application lifetime under AppState and the shared bounded
operation owner, avoids unbounded export/report accumulation, and preserves the approved
plain native table/form visual language.

**If the client answers differently:** Exporting an entire multi-page range requires a
streaming repository/export protocol. Recovering history deleted before the current launch
requires a bounded repository query that includes tombstones. Persisting preferences across
launches requires a versioned settings store rather than ad-hoc UserDefaults keys.

## 2026-09-07 — Task 11 fix round 2: durable settings and independent queries

**Supersedes:** The Task 11 in-session deleted-history and 200-record report/export
ruling immediately above. The approved specification requires recovery after
relaunch and complete totals for the selected range.

**Decision:** Persist one version-1 settings envelope, limited to 16 KiB, before
publishing preference changes. Load it before composing AppState and system
controllers. Validate both shortcut components and sound identities; normalize
numeric preferences. A failed write leaves the previously active preferences
intact. Hotkey/login updates preserve runtime values on failure and compensate
their saved candidate; a compensation failure is explicitly surfaced.

**Decision:** History and Reports retain separate filters, loading flags, errors,
request identities, and results. Latest request wins; Cancel invalidates publication
and report pagination checks invalidation before every next page. History shows a
bounded current page (up to 200 rows) and Next page replaces that page. Reports and
CSV read the full active range up to 10,000 rows / 51 bounded page calls. Over-cap
requests fail visibly rather than publishing incomplete totals or replacing data.
CSV failure has its own error and never reloads History. Mutations refresh both
consumers with their respective active filters.

**Decision:** Date-only Through means the complete selected calendar day. Compute
the next local midnight with Calendar (23/25-hour DST days included), then bridge
to the existing inclusive repository API using the immediately preceding
representable Date. Never subtract a fixed second or millisecond.

**Decision:** Recently Deleted discovers the latest 200 durable history tombstones
from Core Data. Retention is unlimited by default; finite retention runs at load,
when changed, and daily, in at most 50 batches of 200. A remaining backlog offers
Retry retention. Twelve-hour input requires explicit am/pm, while 24-hour mode
also accepts explicit am/pm. Formats use the same preference across history,
timer rows, and the status item. Hiding an idle status icon leaves the text
TopTimer so Settings remain reachable.

**Why:** Separate query ownership prevents cross-window corruption; bounded full
range aggregation preserves report meaning; durable preferences and tombstones
make relaunch behavior match the visible controls.

**If the client answers differently:** Larger reports need measured streaming or
repository aggregation; changing twelve-hour ambiguity needs a parser ruling and
tests. Longer deleted-history browsing requires a tombstone cursor. A different
retention policy must explicitly decide whether deleted entries also expire.
