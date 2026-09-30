# Sequential timers and cleanup

The requested sequence is 15 minutes Task 1, 15 minutes Task 2, then 30 minutes
Task 3, repeating endlessly. Only the current step runs. Each completed step is
recorded in history. Pause/Resume applies to the current step; Stop ends the loop.

Add a Sequences window reachable from the popover and main window. It provides
editable ordered rows with a task name and duration in minutes, Add task, Remove,
Repeat endlessly, Start sequence, and a current-step indicator. Preserve the
sequence and its current timer across app restarts. Do not launch all steps as
independent simultaneous timers. Existing countdown and stopwatch behavior stays.

Use a separate persisted sequence definition/run linked to the existing durable
timer ID. Advance after the existing repository completion commits. Persist the
next step before scheduling it; recovery must not duplicate the next step. Delayed
wakeups start the next step when the app resumes rather than fabricating an
unbounded backlog of historical cycles. Sequence scheduling works while TopTimer
is running; quitting cannot execute new steps until relaunch.

Saved suggestions get individual Remove controls and Clear saved suggestions.
The timer list gets Delete all timers with a confirmation. Clear everything
removes all timer records, history, deleted records, saved suggestions, and saved
sequences, cancels their notifications, and stops any active sequence. App settings
and imported sounds remain. Bulk cleanup must cover the entire store, including
records beyond the 100 visible rows. Clearing must not recreate suggestions or a
sequence on the next tick.

Verify deterministic step ordering, endless wraparound, pause/resume, Stop,
relaunch recovery, persistence failures, and interaction with single timers.
Exercise rendered Start sequence, Add/Remove task, clear-suggestion controls,
Delete all timers, and confirmation Cancel/Confirm. Verify cleanup against more
than 100 stored records and a fresh store read. Run the full suite and package
the final app before replacing the older installed copy.

The simplest alternative is a one-line comma-separated sequence command. A
dedicated editable sequence window is recommended because it makes task order,
duration units and repeat behavior explicit. A general automation/rules editor
would add unnecessary complexity for this request.
