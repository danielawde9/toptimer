# Task 10 quality fix round 5

Status: implemented, verified, ready for independent review. Base: `01924d9`.

## Root causes and fixes

1. AppState's real NotificationController conformance called schedule with the
   authorization flag's false default. Added an explicit scheduleCreatedTimer
   protocol boundary and used it only after a countdown insert succeeds. The
   concrete conformance requests authorization only while status is undetermined;
   stopwatch creation and failed inserts do not request it. Denial remains in
   AppState.notificationStatus.
2. The TimerItem alert name was discarded by the application adapter and the UN
   adapter always selected the default sound. NotificationRequest now carries
   the prepared sound identity. The real UN adapter prepares named audio and
   constructs UNMutableNotificationContent with UNNotificationSound(named:).
   AppState validates a new sound before persisting editor changes, preserving
   the previous settings when preparation fails.
3. The repository's incoming-active-state gate rejected legitimate domain
   terminal operations. Acknowledgement also stamps deletedAt, conflicting with
   the generic deletion guard. The repository now permits only exact replays of
   acknowledgement, terminal restart, metadata update, or reconfiguration, still
   enforcing identity, lineage, revision CAS and whole-value equality. An
   acknowledged archive timestamp is distinguished from unrelated soft deletion.
4. The editor exposed an editable kind even though reconfiguration rejects kind
   changes. Kind is now a visible, read-only label. Recurrence and other controls
   remain available.
5. The native coordinator returned true for Up/Down even when the reducer said
   passThrough. It now returns false. A separate selectSuggestion effect handles
   actual suggestion navigation; no suggestions and IME composition pass through.
   An absent field editor no longer accidentally means composition is active.

## Sound and volume treatment

The per-timer volume slider remains functional and is labelled In-app alert
volume. TopTimerApplication injects the existing AlertSoundController into
AppState. Both automatic due processing and explicit completion invoke it after
durable completion with the chosen source URL and volume. Sequential retries of
an already completed timer do not replay the sound. The existing playback
controller's fallback remains in place.

OS notifications independently carry the chosen sound. Their volume is
controlled by macOS; the editor explains that boundary. No critical-alert API,
entitlement, or claimed ordinary notification-volume control was introduced.

Apple's installed SDK UNNotificationSound.h specifies Library/Sounds in the app
data container/app group or the app bundle as the named-sound search location.
The normal named-sound API does not expose the volume parameter of the separate
critical-alert APIs. Also consulted Apple's
[UNNotificationSound documentation](https://developer.apple.com/documentation/usernotifications/unnotificationsound)
and [local notification guide](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html).

LocalNotificationSoundPreparer copies input through the existing no-follow,
exclusive, 20 MB file boundary and converts supported decoded audio into PCM CAF
under Library/Sounds. It accepts nonempty audio through 30 seconds, mono/stereo,
at most 192 kHz, uses 4,096-frame buffers, and never overwrites an existing staged
file. Cache inspection stops at 1,000 children and admission is capped at 100
files including in-flight preparations. File identity is a hash of the stable
sound name. Invalid/overlong audio and cache failures are explicit errors.

## RED evidence

All commands ran in the requested TopTimer worktree on 2026-09-07.

- `swift test --filter Task10Round5BoundaryTests`: real AppState/controller/Core
  Data creation test showed zero authorization calls instead of one and
  notAuthorized(notDetermined) instead of authorizationDenied (16:52:40).
- `swift test --filter 'testTerminalUpdatesReplay|testCompletedTimerAllowsEditor'`:
  both real Core Data terminal tests threw staleTimerUpdate (16:53:24). The first
  repair still rejected acknowledgement due to its deletedAt stamp, pinpointing
  the second guard; exact replay resolves both restrictions.
- `swift test --filter testEditorDoesNotOfferImmutableKindChanges`: the mounted
  editor still offered a Stopwatch picker option (16:54:24).
- `swift test --filter testNativeCoordinatorPassesArrowCommandsThrough`:
  four assertions failed for Up/Down with no suggestions or composition
  (16:55:10). After passing those commands through, a separate regression test
  exposed missing consumption of actual suggestion navigation (16:55:57),
  fixed with the explicit selectSuggestion effect.
- `swift test --filter NotificationSoundBoundaryTests`: compilation RED for
  missing alertName propagation, soundName request, actual UN content builder,
  and LocalNotificationSoundPreparer (16:57-16:59).
- `swift test --filter testDueAndExplicitCompletionPlaySelectedSound`:
  compilation RED for the absent AppState playback boundary (17:00).
- `swift test --filter testFailedSoundPreparationPreservesPersistedChoice`:
  failed configuration returned true and replaced Glass with Ping despite
  preparation failure (17:01:18). Preparation now precedes persistence.
- `swift test --filter testConcurrentPreparationsCannotExceedCacheCapacity`:
  concurrent preparations produced 101 cache files against a 100-file limit
  (17:07:05). In-flight admission reservations now preserve the bound across
  actor suspension.

Test-harness corrections: an initial XCTest helper naming collision was fixed
before interpreting failures; a submillisecond Date fixture was replaced with
a fixed timestamp to match canonical persistence; the two pre-existing complete
operation-order expectations now include the new durable-state read, preserving
all original persistence/effect/publication assertions. The rendered picker-count
expectation changed from four to three because kind is intentionally read-only,
and a new test explicitly rejects the removed mutable kind option. No tests were
deleted or assertions silently dropped.

## GREEN and visual proof

- Final `swift test`: **219 tests, zero failures** at 17:07:57, recorded in
  `.build/round5-full.log`.
- Focused boundary/repository run: 58 tests passed before the additional cache
  concurrency test; that test separately passed and is included in the full 219.
- Strict debug build: `swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` — passed.
- Strict release build: `swift build -c release -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` — passed.
- `git diff --check` — clean.
- Native editor hosting tests exported light/dark proof to
  `.build/task10-round5-light` and `.build/task10-round5-dark`. Inspected both:
  read-only kind, recurrence controls, preserved volume slider and precise
  macOS notification-volume explanation are visible and fit the form.
- Real audio-file tests read the resulting CAFs with AVAudioFile and prove
  valid duration, selected identities, traversal/link rejection, overlong-audio
  refusal, unchanged existing-file bytes, and the cache concurrency bound.
- Actual UNMutableNotificationContent is compared with the expected named
  UNNotificationSound and against the default sound. In-app propagation uses the
  real AlertSoundController with an injected player and a real repository that
  the player queries to prove persistence occurred before playback.

## Files and concerns

Changed AppState, QuickEntryCommandReducer, QuickEntryTextField, QuickEntryView,
TimerEditorView, TopTimerApplication, TimerRepository, NotificationController;
added NotificationSoundPreparer and two boundary-test files. Existing rendered,
AppState and repository tests were extended. Decisions and lesson detectors are
appended to docs/decisions.md and docs/lessons.md.

No actual OS permission dialog or audible packaged-app playback was triggered
by the test suite. Native content/file construction and sound-player propagation
are proven; speaker output, notification/in-app acoustic overlap and a full IME
or VoiceOver session remain release smoke-test concerns.

An unrelated lifecycle issue was observed while initially simulating a failed
insert by closing the real store: inserting after CoreDataStore.close can raise
an Objective-C exception rather than a Swift error. The fixture now uses an
injected insert failure; this separate store-lifecycle issue was reported to the
controller and left outside this repair round.

No push or deployment performed.
