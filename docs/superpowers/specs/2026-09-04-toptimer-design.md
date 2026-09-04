# TopTimer design specification

- **Status:** Approved for implementation on 2026-09-04
- **Product:** TopTimer
- **Platform:** macOS 13.5 and later
- **Distribution:** Open source under the MIT license

## 1. Product intent

TopTimer is a fast, native menu-bar timer for people who want to start and monitor
time without switching context. It provides the publicly documented capabilities
of Horo's timer workflow plus explicit multi-timer recurrence, while using an
original product name, icon, interface, and codebase.

The app is a menu-bar utility with no normal Dock presence. It works offline,
collects no data, and requires no account.

Reference used to define public feature parity:
[Horo — Mac App Store](https://apps.apple.com/us/app/horo-timer-for-menu-bar/id1437226581?mt=12).

## 2. User-visible capabilities

### 2.1 Fast entry

The menu-bar item opens a compact popover with a focused text field. Pressing
Return or the visible Run/Play control starts the entered timer. Supported forms
include:

- `15m`, `1.5h`, `1h 20m`, and `60s`;
- `1:30:45` for hours, minutes, and seconds;
- `@3pm` and `@14:30` for a countdown to a wall-clock time;
- an optional title and one or more `#tags`, such as
  `25m Design review #client`;
- blank input for a stopwatch that starts at `00:00` and counts upward.

Bare numbers use minutes by default. Invalid or ambiguous input remains in the
field and displays a concise correction next to it.

Recent valid entries, tags, and saved presets appear as keyboard-navigable
suggestions. Suggestions are capped at 20 items.

The expanded editor provides a title, an optional description of up to 500
characters, and up to 12 tags of 32 characters each. A description is not
required to start a timer and never slows down quick entry.

### 2.2 Timers and stopwatches

The app can run multiple independent timers and stopwatches. Each item supports:

- a user-visible title, optional description, and tags;
- start, pause, resume, restart, duplicate, edit, and delete;
- a selected built-in alert or imported sound and volume;
- optional recurrence;
- creation, start, pause, completion, and deletion timestamps.

The menu bar displays the active countdown that will finish first. If only
stopwatches are active, it displays the oldest running stopwatch. Completed items
remain visible until acknowledged, restarted, or removed.

### 2.3 Recurrence

Recurrence is disabled by default and chosen separately for every countdown:

- fixed interval after completion;
- daily at a selected local time;
- weekdays at a selected local time;
- weekly on one weekday and local time;
- selected weekdays at a selected local time.

Completion creates at most one next occurrence. The engine persists the generated
occurrence identity before notifying, making duplicate future occurrences
impossible after a crash or relaunch. Calendar recurrence follows the Mac's
current time zone. During daylight-saving changes, a nonexistent local time moves
to the next valid local time; a repeated local time uses the first occurrence.

### 2.4 Notifications and sound

TopTimer requests notification permission in context when the first timer is
created. A completed timer notification shows the title and, when present, the
first 120 characters of its description. It provides these actions:

- **Stop** acknowledges the completion;
- **Repeat** starts the same duration again;
- **Snooze** starts a five-minute countdown.

Settings can change the snooze duration. Notification denial never blocks a
timer. The popover shows a persistent permission status with an action to open
macOS Notification Settings.

Built-in sounds work without file access. An imported sound is validated, copied
into TopTimer's Application Support directory, and referenced by stable identity.
If playback fails, the app records the failure and uses the built-in fallback.

### 2.5 History and reports

Every stopped or completed run creates a history record. The history window
supports:

- date-range and tag filters;
- title, description, and tag search;
- editing a past record;
- soft deletion and recovery;
- totals by timer and tag;
- daily and weekly charts;
- CSV export using UTF-8 and stable column names.

CSV exports include title, description, and tags as separate columns.

The initial history view loads at most 200 records. Additional records use cursor
pagination. Reports query only their requested date range.

### 2.6 Preferences and shortcuts

Preferences include:

- menu-bar format and whether to show an icon;
- a global shortcut to open quick entry;
- a global shortcut to pause or resume the priority timer;
- default alert, alert volume, and snooze duration;
- launch at login;
- prevent Mac sleep while at least one timer runs;
- 12-hour or 24-hour wall-clock parsing and display;
- history retention, with unlimited retention as an explicit option.

## 3. Visual and interaction design

The approved direction is a reduced native utility. The timer is the interface.
There is no product header, marketing copy, card grid, gradient, or decorative
dashboard treatment inside the popover.

### 3.1 Tokens

- Popover background: neutral `#242424` in dark appearance, system material in
  light appearance.
- Primary text: system label color.
- Secondary text: system secondary label color.
- Timing accent: `#6F9BFF`.
- Secondary active signal: `#FFB65A`.
- Typography: San Francisco system type with tabular countdown numerals.
- Outer radius: 8 points. Control radius: 6 points.

### 3.2 Quick-entry popover

The default popover is approximately 260 points wide. Its first row contains an
original TopTimer mark and the borderless entry field. A compact toolbar contains
settings, Run/Play, timer list, and quit controls. Run/Play starts the parsed
countdown or starts a stopwatch when the field is empty. Every control has a
tooltip, accessibility label, visible keyboard focus, and a minimum 28-point
pointer target.

### 3.3 Timer list

The expanded list is approximately 340 points wide. Each row shows title, tags,
tabular remaining time, end time, recurrence summary, and a two-point progress
line. The full description appears in the detail editor rather than crowding the
list. Controls appear on hover and keyboard focus without shifting row layout.
The list is scrollable and renders at most 100 rows in one view.

Reduced-motion settings disable nonessential transitions. Increased contrast,
VoiceOver, keyboard-only operation, light appearance, and dark appearance are
supported.

## 4. Architecture

TopTimer uses a Swift Package as the buildable source of truth and packages the
executable into a standard `.app` bundle. SwiftUI owns views and scene lifecycle.
Small AppKit adapters own status-item behavior and integrations unavailable in
pure SwiftUI.

Modules have narrow responsibilities:

- **TimerDomain:** timer types, state transitions, recurrence rules, parser, and
  formatting;
- **TimerEngine:** clock-driven orchestration and priority selection;
- **Persistence:** Core Data entities, repositories, migrations, and bounded
  history queries;
- **Notifications:** permission state, scheduling, categories, and action routing;
- **SystemIntegration:** global shortcuts, login item, sound, and sleep assertion;
- **TopTimerApp:** menu-bar scenes, popover views, history, reports, and settings.

TimerDomain has no dependency on SwiftUI, Core Data, or wall-clock globals. The
engine receives a clock and repositories through explicit protocols so tests can
advance time without sleeping or mocking framework internals.

## 5. Data flow and invariants

A timer stores an absolute deadline while running and an exact remaining duration
while paused. UI refresh ticks only redraw formatted values; ticks do not mutate
remaining time. This prevents drift during sleep or process suspension.

Creating a timer follows this sequence:

1. Parse and validate bounded input.
2. Persist the timer and recurrence configuration.
3. Schedule its notification when permission allows.
4. Publish the saved timer to the interface.

Completion follows this sequence:

1. Atomically mark the occurrence complete and append its history record.
2. Atomically persist the next recurrence identity when recurrence is enabled.
3. Schedule the next notification.
4. Deliver the completion alert and refresh the interface.

Required invariants include positive countdown duration, bounded titles,
descriptions, and tags, one history completion per occurrence, and at most one
successor occurrence.

## 6. Failure behavior

- Invalid input remains editable and states exactly what could not be parsed.
- Notification denial is visible and recoverable but never stops timing.
- Failed notification scheduling is logged locally without timer content and
  surfaced as a nonblocking status.
- Missing imported sounds fall back to a built-in alert.
- Core Data save failures keep the unsaved draft visible and do not schedule a
  notification for data that was not persisted.
- Global-shortcut conflicts identify the conflicting shortcut and leave the
  previous valid shortcut active.
- Sleep assertions are always released when the last running timer stops or when
  the process exits.

No log contains timer labels, tags, exported rows, file contents, or other user
data.

## 7. Verification design

Test-driven implementation covers:

- every supported parser form and invalid-input boundary;
- start, pause, resume, completion, restart, and stopwatch transitions;
- simultaneous timer priority selection;
- recurrence uniqueness and calendar behavior across DST transitions;
- persistence recovery after relaunch and schema migration;
- history totals, metadata search, filtering, editing, soft deletion, and
  pagination;
- stable RFC 4180-compatible CSV export;
- notification scheduling and action routing through protocol fakes;
- menu-bar formatting and accessibility identifiers.

Before installation, the full test suite, warning-as-error build, release package,
and app-bundle validation must pass. Human-flow smoke testing covers first launch,
notification permission, natural-language creation, two simultaneous timers,
pause/resume, completion notification, repeat, recurrence, quit/relaunch recovery,
history, CSV export, settings, keyboard shortcuts, and menu-bar appearance.

## 8. Delivery and acceptance criteria

Delivery includes:

- complete source with no closed or paid feature flags;
- an MIT license, contributor guidance, architecture notes, and build instructions;
- a local Git repository with conventional commits and no configured remote;
- a locally built app installed as `/Applications/TopTimer.app`;
- a launched menu-bar process verified after installation.

The release is accepted when the verification in section 7 passes in the delivery
session and every capability in section 2 is reachable from the packaged app.

Signing is ad hoc for this local build. Public distribution through GitHub or the
Mac App Store requires the owner's Apple Developer signing and notarization setup,
which is outside this local delivery unless separately requested.
