# Sequential timers and cleanup implementation plan

**Goal:** Run editable task sequences endlessly and expose complete cleanup.
**Architecture:** A persisted sequence coordinator links one planned timer to the
existing repository. Write its next timer ID before insertion so recovery can
retry insertion without duplicating a step. Use store-wide Core Data deletion
transactions for cleanup, including records beyond visible page limits.
**Tech stack:** Swift 6, SwiftUI/AppKit, Core Data, XCTest.

- [x] Add coordinator and bulk-cleanup regression tests using isolated stores.
  Verify three steps wrap, pause blocks advancement, stop survives reload, a saved
  planned timer resumes after reload, and 105 timers/presets are all removed.
- [x] Add validated sequence steps/session and a JSON sequence store; implement
  start, reconciliation, advance, stop, saved-definition loading and removal.
- [x] Add repository `removeAllTimers()` and `clearAllData()` plus preset
  `removeAllPresets()` using one save/rollback per cleanup transaction.
- [x] Integrate the coordinator with AppState refresh/load and timer mutations;
  expose sequence state, suggestion removal and bulk cleanup with errors.
- [x] Add Sequences window and navigation, editable task rows, repeat toggle,
  Start/Pause/Resume/Stop controls. Add individual suggestion Remove controls,
  clear-suggestions and confirmed Delete all timers/Clear everything actions.
- [x] Exercise rendered buttons and existing regressions, capture the new window,
  run `swift test`, package/verify the release app and replace the old installed
  copy after tests pass. Preserve settings and the earlier recovery backup.

User navigation follow-up: every app window now has a native Go to menu for all
six screens. Toolbar menu actions and real controller destinations are tested.
Final verification: 317 ordinary tests passed, optional screenshot test passed
separately, 30 synthetic captures reviewed, release warnings-as-errors and bundle
verification passed. Updated /Applications/TopTimer.app with a recoverable app
backup; actual timer/history/preset tables remain empty.
