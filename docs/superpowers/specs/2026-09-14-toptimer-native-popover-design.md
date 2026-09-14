# TopTimer native popover and shortcuts redesign

## Goal

Make the menu-bar surface feel like a fast, calm macOS timer utility. Starting
a timer is the first action when none runs; an active timer is the first thing
seen when one exists. Settings must be obvious and shortcut configuration must
not expose Carbon key codes as the main interaction.

## Scope

This design replaces only the status-bar popover and the Shortcuts section of
Settings. Timer persistence, parsing, notifications, global hotkey registration,
history, and timer domain behavior remain unchanged.

## Popover

The popover is 320 points wide, transient, and anchored below the status item.
It has one stable hierarchy:

1. A single-line command field at the top, focused on opening when no timer is
   active. Return starts the entered countdown or blank stopwatch.
2. Contextual body:
   - With no active timer: a short `No timer running` state and at most three
     recent commands, each a full-width selectable row.
   - With an active timer: title, monospaced remaining time, and clear text
     controls for Pause/Resume and Stop/Finish. `Start another timer` reveals
     the command field without displacing the active timer.
   - With more timers: show only the priority timer and a text `All timers…`
     action that opens the existing timer-list window.
3. A quiet bottom bar with text actions: `Settings`, `All timers`, and `Quit`.
   It remains visible while the middle content scrolls.

The popover does not show a long, unbounded suggestion list. Suggestion and
active-timer body content scroll independently below a bounded height; the input
and bottom actions never move out of view.

## Shortcuts

The Settings section uses two straightforward rows: `Quick entry` and
`Pause/resume priority timer`. Each row shows its current combination in a
readable key-cap treatment, or `Not set` when disabled, followed by a
non-destructive `Change…` action and an `Unset` action only when a shortcut is
currently enabled.

`Change…` opens a small native sheet that says `Press the shortcut you want to
use` and captures the next valid modifier-plus-key combination. Escape cancels
without changing the registered shortcut. Conflicts and unsupported combinations
are explained in that sheet. The raw numeric key code is not displayed.

## Error and accessibility behavior

Actions use visible labels as well as accessibility labels. Keyboard focus
progresses input, contextual controls, then bottom actions. Errors appear near
the triggering control and preserve the prior registration. The popover remains
usable with long timer titles by truncating titles visually while retaining the
full accessible label.

## Verification

- Unit test popover geometry and persistent bottom actions.
- UI tests for no-timer, active-timer, multiple-timer, suggestions, and shortcut
  capture/unset states.
- Installed-app click-through: open from status item, open Settings, change and
  unset each shortcut, relaunch, and verify the disabled shortcut no longer fires.

## Stop conditions

Do not alter timer state/domain semantics, notification delivery, or history.
Do not claim installed-app completion without an observed live click-through.
