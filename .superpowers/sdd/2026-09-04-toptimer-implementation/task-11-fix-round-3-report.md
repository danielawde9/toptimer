# Task 11 fix round 3

Base: 6d9c2b6. All three requested findings addressed. No push.

## Changes and root causes

1. Show all history previously changed the backend query while leaving dated
   controls visible. HistoryFilterControls now belongs to AppState and includes
   an explicit All time choice. The actual empty-state action sets All time and
   clears search, then applies the shared model. Date controls are hidden in this
   mode. A behavior test follows the action through visible model, applied filter,
   edit/delete/recover refreshes, and CSV query; all five queries are all-time.

2. Startup previously propagated every settings decode error into the fatal
   startup Retry loop. The strict bounded decoder remains unchanged, while
   loadForStartup resets invalid settings to normalized defaults and returns a
   warning. The app starts normally and presents the warning in Quick Entry and
   Settings. Successful reset persists a valid versioned envelope. Failed reset
   leaves original bytes intact, runs on defaults, and exposes a Save recovered
   settings and acknowledge action. Tests cover malformed, unknown-version,
   oversized, write-failure/retry, and a fresh UserDefaults store instance.

3. Settings errors previously lived outside the Form's scrolling area. They now
   live in a Status and recovery section within that same Form. Window geometry
   constrains the viewport; controls and all messages remain scrollable. The
   rendered regression creates four simultaneous operation errors plus a startup
   recovery warning in a 700 by 520 native window, verifies a fitting height no
   larger than the viewport, proves content overflow, and scrolls to the end.

## RED/GREEN evidence

- Task11Round3Tests initially failed because the explicit control model,
  current-filter seam, startup recovery API, and recovery retry were absent.
- The native simultaneous-error regression then failed on the real old layout:
  fitting height 826 exceeded the 520-point window. Moving messages into the Form
  alone still exposed its unconstrained ideal height (1042.5); constraining the
  viewport by window geometry made the same test pass.
- All five focused regressions pass. Existing decoder rejection tests still pass.

## Final verification

- swift test: 256 tests passed, 0 failures.
- swift build -Xswiftc -warnings-as-errors: passed.
- swift build -c release -Xswiftc -warnings-as-errors: passed.
- git diff --check: passed.
- TOPTIMER_TASK11_ROUND3_PROOF=/tmp/toptimer-settings-recovery.png swift test
  --filter Task11Round3Tests: 5 passed.

Inspected /tmp/toptimer-settings-recovery.png: at the bottom of the default-size
window, every simultaneous error and the recovery-save action is visible without
clipping. Native scrolling is tested; full VoiceOver navigation is not claimed.
Decisions and executable regression lessons were appended to their ledgers.
