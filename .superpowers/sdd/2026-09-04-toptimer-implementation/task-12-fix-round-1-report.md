# Task 12 fix round 1 report

## Outcome

Packaging now validates the complete 1.0.0 bundle contract and publishes only a
fully verified candidate. A forced failure after candidate verification preserves
an existing signed output byte-for-byte. The handover accurately identifies the
local artifact as Apple silicon (`arm64`) only and separates SwiftPM's `.build`
output from the final `build/TopTimer.app` publication boundary.

## Strict TDD evidence

Negative behavior tests were written before production changes.

- The initial verification-contract run reported ten RED cases. The current
  verifier wrongly accepted mutated executable name, icon name, package type,
  short version, build version, minimum system, a non-Mach-O executable, an empty
  icon, and an invalid nonempty icon. The identifier fixture was rejected with the
  old generic message rather than the exact contract error.
- Existing LSUIElement and signature checks correctly rejected their fixtures.
- The initial transactional test set
  `TOPTIMER_TEST_FAIL_AFTER_CANDIDATE_VERIFY=1`; the old packager ignored it,
  returned success, and replaced the prior bundle. The test failed with
  `Expected forced late packaging failure`.

After implementation, the fixtures reject every required plist field plus invalid
plist, missing/non-executable/non-Mach-O/unsupported-architecture executables,
missing/empty/invalid ICNS resources, and an invalid signature. The transactional
test adds a signed sentinel to a valid prior bundle, fingerprints all bundle files,
forces a late candidate failure, and proves the fingerprint and verification are
unchanged afterward.

## Implementation

- `verify-app.sh` now requires exact values for `CFBundleExecutable`,
  `CFBundleIconFile`, `CFBundlePackageType`, `CFBundleShortVersionString`,
  `CFBundleVersion`, `LSMinimumSystemVersion`, `LSUIElement`, and
  `CFBundleIdentifier`.
- The executable must be executable Mach-O and `lipo` must report at least one
  architecture, with every architecture restricted to `arm64` or `x86_64`.
- The icon must be nonempty and successfully extract through `iconutil`; temporary
  verification output is one exact `mktemp` directory and cleanup removes only it.
- Strict code-signature verification and explicit `Signature=adhoc` remain required.
- `package-app.sh` creates one exact temporary child within repository `build`, then
  assembles, generates the icon, signs, and verifies its candidate there. It does
  not touch the published destination before candidate acceptance.
- Publication moves the existing exact destination to a same-volume backup, moves
  the accepted candidate into place, and removes the backup only after success.
  Exit cleanup restores the backup when the destination is absent. If a destination
  appears concurrently, cleanup preserves the backup and reports its exact path.
- README, architecture notes, and the append-only decision ledger distinguish
  `.build` compiler output from the final bundle boundary and document the measured
  `arm64`-only local package without claiming Intel support.

## Fresh verification

The final gate on 2026-09-07 exited 0:

```text
bash -n scripts/package-app.sh scripts/verify-app.sh \
  Tests/Packaging/package-safety-tests.sh \
  Tests/Packaging/verification-contract-tests.sh \
  Tests/Packaging/transactional-package-tests.sh
bash Tests/Packaging/package-safety-tests.sh
bash Tests/Packaging/verification-contract-tests.sh
bash Tests/Packaging/transactional-package-tests.sh
swift test
swift build -c release -Xswiftc -warnings-as-errors
bash scripts/package-app.sh
bash scripts/package-app.sh
bash scripts/verify-app.sh build/TopTimer.app
git diff --check
```

Results:

- Packaging safety tests passed.
- Verification contract tests passed.
- Transactional packaging test passed.
- 256 Swift tests passed with 0 failures and 0 unexpected failures.
- Strict release build completed without warnings.
- Both consecutive package runs verified their candidates and published cleanly.
- Final bundle verifier printed `TopTimer.app verified`.
- Diff check passed.
- `lipo -archs` reports exactly `arm64`.

## Reinstallation proof

The changed final bundle was installed safely. The prior exact installed bundle was
quit and moved recoverably to
`/Users/daniel/.Trash/TopTimer-20260907-184143.app`. The final verified bundle was
copied to `/Applications/TopTimer.app`, verified at the installed path, and its
executable compared byte-identically with the build output. Launch proof:

```text
installed_bundle=/Applications/TopTimer.app
architectures=arm64
process_count=1
39966 /Applications/TopTimer.app/Contents/MacOS/TopTimer
```

## Boundaries

No push, merge, publication, notarization, GitHub operation, Developer ID signing,
or Intel build was performed. The earlier native human-flow and VoiceOver acceptance
limitations remain unchanged; this round was restricted to packaging contract,
transactionality, artifact architecture, and handover accuracy.
