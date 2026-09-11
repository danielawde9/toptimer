# TopTimer Now Window Design

## Purpose

TopTimer must make its running state understandable on first use. A person must
always be able to answer three questions without remembering a shortcut or
deciphering a menu-bar label: what is running, what will happen when they close
the interface, and how they can control it again.

This design replaces the transient menu-bar popover as the product's primary
surface. It does not change timer, recurrence, history, notification, or local
storage rules.

## Product rule

An active timer persists when TopTimer quits. "Quit" ends the TopTimer process,
not the timer's durable schedule. The next launch opens the Now window and
explains the recovered state. A timer that expired while the process was absent
is completed exactly once and appears in a small recovery message and History.

Closing the Now window hides the interface only. It never pauses, stops, or
deletes a timer. The menu-bar item remains as the visible return path while the
process is running.

## Information architecture

### Now window

The Now window is the default window on every launch and the target of every
menu-bar click and Quick Entry shortcut. It has one responsibility: create and
control current timers.

It contains, in this order:

1. A single natural-language entry field and Start button. It is focused only
   when there is no active timer or when the user invokes the Quick Entry
   shortcut.
2. A primary timer summary when at least one timer is active: title, explicit
   Running or Paused state, exact remaining/elapsed time, progress, Pause or
   Resume, and Stop or Finish. These actions are always visible, not hidden in
   a hover-only menu.
3. A compact list of the other active timers, each with a labelled state,
   time, and an Actions menu. More than three uses a Show all active timers
   action that opens the existing Timer List window.
4. A small toolbar: History, Settings, and Quit. Reports remains reachable from
   History/Timer List rather than competing with the first-use surface.

The empty state says "Start a timer" and includes three selectable examples:
`25m focus`, `10m tea`, and `stopwatch reading`. It does not show history,
reports, deletion controls, configuration, or a decorative dashboard.

### Menu bar

The status item is a mirror and return path, never the only place to operate
the app. While a timer runs, it shows the priority timer's remaining time plus
a count for additional timers (for example, `12:04 +2`). Its accessibility
label includes the timer title, state, remaining or elapsed time, and the
additional-timer count. Its tooltip says "Open TopTimer" and names the active
timer. With no active timer it shows the TopTimer icon and title.

Clicking the item always shows and brings forward the Now window. It never
toggles a transient popover. Closing that window leaves the status item in
place; successfully quitting removes it.

### Quit and recovery

Every quit route, including the visible Quit button and Command-Q, uses the
same policy.

- With no active timers, quit immediately.
- With running or paused timers, show a native confirmation: "Timers keep their
  state while TopTimer is closed." It describes running timers as continuing
  toward their saved deadline and paused timers as remaining paused. The
  actions are `Quit and keep timers` and `Cancel`; Cancel is the default.
- After `Quit and keep timers`, TopTimer drains outstanding work, closes local
  resources, removes the status item, and exits. It never cancels a timer or
  its notification merely because the app exits.
- On the next launch, the Now window is visible. It shows either `1 active
  timer recovered` / `N active timers recovered` or `N timers finished while
  TopTimer was closed`, with a dismissible History action. Messages must name
  no timer content until that content is displayed in the window itself.

## State contract

| State | Now window | Status item | Safe action |
| --- | --- | --- | --- |
| First launch, no timers | Focused entry and examples | TopTimer | Start a timer |
| One running countdown | Primary timer, Running, Pause, Stop | time and title/count | Pause or Stop |
| One running stopwatch | Primary timer, Running, Pause, Finish | elapsed time and title/count | Pause or Finish |
| One paused timer | Primary timer, Paused, Resume, Stop/Finish | paused label and title/count | Resume or stop |
| Multiple active timers | Priority timer plus up to three others | priority time plus `+N` | Show all timers |
| Window closed | No window | truthful active or idle indicator | menu-bar click opens Now |
| Quit requested with active timers | native confirmation | unchanged until exit | Quit and keep / Cancel |
| Relaunch, still-active timers | recovered-state message and controls | truthful priority | continue control |
| Relaunch, expired timers | finished-while-closed message, History action | idle or next active timer | inspect History |
| Notification denied | non-blocking warning and Open Notifications Settings | still truthful; never implies alert delivery | open Settings |
| Storage/startup failure | native failure controller with Retry/Quit | failure item | recover or quit |
| Timer mutation failure | inline error beside the action; timer state does not lie | last durable state | Retry / inspect timer |

## Lifecycle and data rules

The database remains the source of truth. Running countdowns retain their
absolute deadlines; paused timers retain their stored remaining duration. On
startup, TopTimer first settles durable timers due before the launch time, then
publishes active timers. This avoids briefly displaying an expired timer as
running. Completion must remain idempotent: reopening twice cannot append two
history records or schedule two recurrence successors.

The application records a presentation-only startup summary while it settles
timers. It is not persisted. It distinguishes active recovery from one or more
completions settled during launch so the Now window can explain the outcome
without altering the timer/history schema.

## Accessibility and native behavior

The Now window uses ordinary labelled SwiftUI buttons and controls. The primary
timer's state and time are exposed as one accessible summary; action labels say
Pause, Resume, Stop, or Finish rather than icon-only controls. Keyboard focus
starts in the entry field only when that does not steal focus from an active
control. Escape closes the window; it does not quit or stop a timer. Command-Q
uses the same confirmation policy as the visible Quit button.

Both light and dark appearances, VoiceOver labels, keyboard-only operation,
and Dynamic Type-compatible native layout must be checked in the installed
app. No claim of completion may rely only on rendered view tests.

## Out of scope

- Changes to parsing syntax, recurrence semantics, history schema, reports,
  CSV export, settings data, or notification authorization behavior.
- Cloud sync, accounts, mobile clients, dashboard analytics, or a custom
  visual brand treatment.
- Treating app quit as a timer stop/cancel action.

## Acceptance criteria

1. A first-time user can create, see, pause/resume, stop, and find a timer
   again without opening a menu-bar popover.
2. A status-bar click always reveals a usable Now window.
3. Quit explicitly explains durable active/paused timers, exits the process,
   and leaves no status item behind.
4. Relaunch gives a clear recovery outcome and correct durable timer/history
   state, including overdue countdowns and recurrence successors.
5. All states in the table have automated coverage where practical and an
   installed-app Pass/Fail/Blocked audit with screenshots.
