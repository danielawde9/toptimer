# TopTimer Now-window installed-app audit

Exact source baseline: `bebe1de` (feature worktree: `feat/toptimer-now-window`).
Installed target: `/Applications/TopTimer.app`. Personal timer titles are not recorded.

Package command: `bash scripts/package-app.sh` — passed; `TopTimer.app verified`.
Install command: `ditto build/TopTimer.app /Applications/TopTimer.app` — completed.
Build/installed executable SHA-256: `91365530b0b0c2ef05510393454827f91a2bf1d32c1662b1d59fd6cbe43c66b0` (match).
Pre-audit process was present at PID 76271. Native Computer Use attach to the installed
menu-bar app timed out with `Computer Use server error -10005: timeoutReached`.

| Flow | Status | Evidence / blocker |
|---|---|---|
| First launch | Blocked | Native installed-app attach timed out before interaction. |
| Active countdown | Blocked | Native installed-app attach timed out before interaction. |
| Active stopwatch | Blocked | Native installed-app attach timed out before interaction. |
| Paused timer | Blocked | Native installed-app attach timed out before interaction. |
| Multiple timers | Blocked | Native installed-app attach timed out before interaction. |
| Close Now window | Blocked | Native installed-app attach timed out before interaction. |
| Visible quit | Blocked | Native installed-app attach timed out before interaction. |
| Command-Q | Blocked | Native installed-app attach timed out before interaction. |
| Relaunch with active timer | Blocked | Native installed-app attach timed out before interaction. |
| Relaunch after expiry | Blocked | Native installed-app attach timed out before interaction. |
| Notification denial | Blocked | Native installed-app attach timed out before interaction. |
| Startup failure | Blocked | Native installed-app attach timed out before interaction. |
| History | Blocked | Native installed-app attach timed out before interaction. |
| Light/dark | Blocked | Native installed-app attach timed out before interaction. |
| Keyboard-only | Blocked | Native installed-app attach timed out before interaction. |
| VoiceOver labels | Blocked | Native installed-app attach timed out before interaction. |

Live installed-app proof must be recorded only after exercising the packaged app; source tests are not UI proof.
