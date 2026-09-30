# Implemented screens

Native SwiftUI/AppKit captures with synthetic timers and an isolated in-memory
Core Data store. These are implemented screens, rather than generated mockups.

| Screen | Light | Dark |
| --- | --- | --- |
| Popover, idle | [Preview](popover-idle-light.png) | [Preview](popover-idle-dark.png) |
| Popover, running | [Preview](popover-running-light.png) | [Preview](popover-running-dark.png) |
| Popover, paused | [Preview](popover-paused-light.png) | [Preview](popover-paused-dark.png) |
| Main window, idle | [Preview](now-idle-light.png) | [Preview](now-idle-dark.png) |
| Main window, active | [Preview](now-active-light.png) | [Preview](now-active-dark.png) |
| Sequence editor | [Preview](sequences-light.png) | [Preview](sequences-dark.png) |
| Running sequence | [Preview](sequences-running-light.png) | [Preview](sequences-running-dark.png) |
| Timer list | [Preview](timers-light.png) | [Preview](timers-dark.png) |
| History | [Preview](history-light.png) | [Preview](history-dark.png) |
| History, empty | [Preview](history-empty-light.png) | [Preview](history-empty-dark.png) |
| Reports | [Preview](reports-light.png) | [Preview](reports-dark.png) |
| Reports, empty | [Preview](reports-empty-light.png) | [Preview](reports-empty-dark.png) |
| Settings | [Preview](settings-light.png) | [Preview](settings-dark.png) |
| Timer editor | [Preview](editor-light.png) | [Preview](editor-dark.png) |
| Shortcut capture | [Preview](shortcut-light.png) | [Preview](shortcut-dark.png) |

## Button verification

`ScreenActionTests` exercises rendered native controls, accessibility actions,
menus, and mouse events against isolated stores. It verifies:

- The current popover preserves suggestion arrows/Return, Space pause/resume,
  Escape clear/close, native field-editor behavior, and IME composition routing.
- Every window’s native Go to menu includes all six screens; controller routing
  opens each destination. Window content uses Go to instead of duplicate
  navigation rows.
- Sequence Add/Remove task → Start → Pause/Resume → Stop, plus sequence navigation.
- Suggestion Remove and Clear saved suggestions, Delete all timers Cancel/Confirm,
  and Clear everything Confirm.
- Pause → Resume → Stop, and the named stopwatch example → Finish.
- Start with invalid input shows visible feedback and creates no timer.
- Open window → Reports and History opens the intended windows.
- Timer menu Pause, Resume, Restart, Duplicate, Stop, Delete, Acknowledge and Start
  persist their expected changes.
- Timer editor Save persists changes; Cancel leaves the saved timer unchanged.
- History Edit → Save changes → Delete Selected → Recover Selected restores the
  edited entry. Delete also works without opening an editor first.
- Delete All opens a confirmation; Cancel preserves history and Confirm moves it
  to Recently Deleted.
- Reports Update and Choose last 30 days refresh the report.
- Unset removes the default registered shortcut through the Settings callback.
- Stop and Finish refresh already-loaded history and reports.

The full Swift suite registers 319 tests, including 17 screen-action tests.
Screenshot capture runs separately when its output environment variable is set. The release build with warnings as errors
and local bundle verification pass. System permission dialogs, real global hotkey
delivery, login registration, notification delivery and sound-file selection need
an interactive check on the installed app; their underlying services retain their
existing automated coverage. The local bundle is ad-hoc signed.

To regenerate the 30 captures:

```sh
TOPTIMER_SCREENSHOTS="$PWD/docs/screenshots/2026-09-30" swift test --filter ScreenSnapshotTests
```
