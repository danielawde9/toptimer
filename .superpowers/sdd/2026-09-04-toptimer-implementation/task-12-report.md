# Task 12 report — packaging, handover, install, and smoke test

## Status

Task 12's source, packaging, documentation, automated verification, exact local
installation, and process launch proof are complete. Native human-flow and
accessibility acceptance remains explicitly unclaimed because the available UI
automation surface could not attach to the running LSUIElement application.

## Delivered

- Added a standard menu-bar-only `Info.plist` for TopTimer 1.0.0 (build 1), bundle
  identifier `com.lelabodigital.TopTimer`, executable `TopTimer`, icon `TopTimer`,
  and macOS 13.5 minimum.
- Added an original Core Graphics icon generator. It renders a midnight square,
  blue circular timing rail, amber center dot, and two white hands at every macOS
  iconset resolution, then invokes `iconutil` to produce `TopTimer.icns`. No Horo
  or other third-party artwork was used.
- Added a bounded packager fixed to `<repo>/build/TopTimer.app`. It resolves its
  repository independently of the caller's working directory, rejects any other
  destination, runs a strict release build, removes only that exact output bundle,
  assembles the app, signs ad hoc, and invokes verification. Its temporary icon
  directory is an explicit `mktemp` child of build and cleanup targets only that
  returned path.
- Added a verifier that rejects `/`, the current home directory, and the repository
  root; verifies an executable, parseable plist, exact LSUIElement and identifier,
  icon, valid strict signature, and specifically `Signature=adhoc`.
- Added behavior-level shell tests for the packaging path boundary and all three
  unsafe verifier paths.
- Added README, contribution guidance, architecture documentation, and an append-only
  packaging decision. Documentation covers features, local-only privacy, complete
  quick syntax including blank Run as stopwatch, tags/descriptions, recurrence,
  notification actions, custom sounds/volume, reports/CSV, build/test/package,
  installation/uninstallation, GitHub remote setup, MIT licensing, Conventional
  Commits, the decision ledger, and Developer ID/notarization limitations.
- The README reserves `docs/screenshots/toptimer-popover.png`; no screenshot was
  committed because a clean private-content-free native capture could not be proven.

## TDD evidence

1. `scripts/verify-app.sh` was created before bundle implementation.
2. `bash scripts/verify-app.sh build/TopTimer.app` exited 1 with exactly
   `TopTimer.app not found`.
3. `Tests/Packaging/package-safety-tests.sh` was created before
   `scripts/package-app.sh`; its initial run failed with exit 127 because the
   packager did not exist.
4. The first safety run after implementation exposed root path canonicalizing as
   `//`; resolving existing directories directly fixed the source and the same test
   then passed.
5. The first packaging integration emitted SwiftPM's unhandled-resource warning.
   Excluding the packaging-only `Resources` directory from the SwiftPM target
   removed the warning while retaining the packager's explicit plist copy.

## Automated verification

Fresh complete gate on 2026-09-07:

- `bash -n scripts/package-app.sh scripts/verify-app.sh Tests/Packaging/package-safety-tests.sh`
  — exit 0.
- `bash Tests/Packaging/package-safety-tests.sh` — `Packaging safety tests passed`.
- `swift test` — 256 tests, 0 failures, 0 unexpected failures.
- `swift build -c release -Xswiftc -warnings-as-errors` — exit 0 with no warnings.
- `bash scripts/package-app.sh` — exit 0; signed bundle and printed
  `TopTimer.app verified`.
- `bash scripts/verify-app.sh build/TopTimer.app` — exit 0 and printed
  `TopTimer.app verified`.
- `git diff --check` — exit 0.
- From `/tmp`, the verifier and packaging safety test both passed via absolute
  script paths, proving current-working-directory independence.

Bundle inspection showed a Mach-O arm64 executable, an ICNS resource, the exact
required plist values, `flags=0x2(adhoc)`, `Signature=adhoc`, and no TeamIdentifier.
The generated 512-point icon was visually inspected against the original-art brief.

## Installation and launch

The initial pre-install read-only check found no `/Applications/TopTimer.app` and no
process at its installed executable path. After the final gate rebuilt the release,
the first installed bundle was cleanly quit, resolved to exactly
`/Applications/TopTimer.app`, and moved recoverably to
`~/.Trash/TopTimer-20260907-182824.app`. The final verified source bundle was then
installed with `ditto`; `cmp` proved the installed and build executables are identical.

Post-install proof:

```text
installed_bundle=/Applications/TopTimer.app
installed_signature=adhoc
process_count=1
33902 /Applications/TopTimer.app/Contents/MacOS/TopTimer
```

The bounded process poll required exactly one full executable-path match.

## Human-flow and visual acceptance

The installed app was launched. Direct UI automation attachment to `TopTimer` timed
out, and the subsequent accessibility inventory listed other enabled applications
but not the running TopTimer LSUIElement app. Therefore the following remain manual
acceptance work and are not claimed: first-run notification state, light/dark and
VoiceOver review, `15m Tea #home`, description editing, two simultaneous timers,
priority title, pause/resume, stopwatch interaction, completion actions, recurrence
successor observation, quit/relaunch recovery, history search/deletion recovery,
CSV export, shortcut conflict, launch-at-login UI, audible custom-sound/volume, and
sleep-prevention release. No README screenshot was captured.

## Delivery boundaries and concerns

- Local signing is ad hoc only; Developer ID signing, hardened-runtime/entitlement
  review, notarization, GitHub creation, publishing, pushing, deployment, and App
  Store work were not performed.
- No remote is configured.
- The installed application is currently running from `/Applications/TopTimer.app`.
- Full product acceptance still requires the manual checks listed above on a host
  where the menu-bar UI can be observed and notifications/audio can be exercised.
