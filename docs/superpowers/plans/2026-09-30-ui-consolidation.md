# UI consolidation

- [x] Move the existing QuickEntryTextField command routing into the current
  MenuBarPopoverView. Preserve suggestion arrows/Return, Space pause/resume,
  Escape clear/close and composition handling; test against real Core Data.
- [x] Remove unused QuickEntryView and PopoverRoot. Move legacy rendered checks
  to the real popover and retain timer-editor ownership checks on the list host.
- [x] Remove in-content navigation callbacks/buttons from NowView, TimerListView,
  TimerListHost and HistoryView. Keep the native Go to menu on every window and
  popover shortcuts. Test all routes through the real coordinator toolbar.
- [x] Run the full suite and refresh screenshots; package, verify and replace the
  installed app with a backup. Preserve user timer data and app preferences.

Verification: all 319 tests passed and 30 native screenshots refreshed. The
focused keyboard regression also passed using an actual Return event and
asserting exactly one running timer. Release packaging and installed-bundle
verification passed. Updated /Applications/TopTimer.app and relaunched it;
previous app and SQLite data backed up with suffix 26a10ccb.
