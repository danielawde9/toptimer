# Screen Designs and Actions Implementation Plan

**Goal:** Implement the approved native macOS mockups and repair broken actions.

**Architecture:** Keep AppState and the repository as the source of truth. Use
shared SwiftUI time/status presentation and the existing WindowCoordinator for
navigation. Test real rendered button actions with isolated in-memory stores.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Core Data, Charts, XCTest.

- [x] Add failing parser and rendered popover regressions for the stopwatch
  example, missing Resume after Pause, missing error feedback, and navigation.
  Run `swift test --filter ScreenActionTests` and the added parser tests.
- [x] Support the explicit `stopwatch` command with validated title/tags; add
  paused-timer presentation without changing running-only priority semantics.
- [x] Implement shared time badges and status labels; update popover and Now
  layouts, running controls, input, examples and visible errors.
- [x] Connect Open window, All timers, History, Reports and Settings through
  StatusBarController and WindowCoordinator. Make list sizing responsive.
- [x] Match history, reports, settings and editor layouts to native mockups;
  preserve table selection, segmented tabs and sheet confirmations.
- [x] Exercise rendered actions against Core Data, capture native screenshots
  in both appearances, run `swift test`, release warnings-as-errors build,
  package and verify `build/TopTimer.app`. Record results and limits.
