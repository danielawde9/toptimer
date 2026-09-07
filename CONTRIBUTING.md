# Contributing to TopTimer

Thank you for improving TopTimer. Keep changes small, native, offline-first, and
straightforward for the next maintainer.

## Development workflow

1. Create a focused branch and write a failing test before implementation.
2. Keep domain logic independent from SwiftUI, Core Data, and global clocks.
3. Validate user and persistence boundaries, bound collections and platform work,
   and preserve local-data privacy.
4. Add an append-only entry to `docs/decisions.md` in the same commit whenever you
   make an assumption or depart from the approved behavior. State the decision,
   reason, and what changes if the owner chooses differently.
5. Run the complete relevant test suite and a warning-free strict build:

   ```bash
   swift test
   swift build -c release -Xswiftc -warnings-as-errors
   git diff --check
   ```

6. For packaging changes, also run:

   ```bash
   bash Tests/Packaging/package-safety-tests.sh
   bash scripts/package-app.sh
   bash scripts/verify-app.sh build/TopTimer.app
   ```

Use Conventional Commit subjects such as `feat:`, `fix:`, `test:`, `docs:`, and
`chore:`. Commit only a green, warning-free step. Do not include timer content,
personal data, credentials, signing identities, or generated local stores.

Changes to recurrence, persistence, notification actions, sounds, or system
integrations need rejection/failure tests as well as success tests. UI changes must
be checked in light and dark appearance, keyboard-only operation, increased
contrast, reduced motion, and VoiceOver; report checks honestly and do not claim
manual coverage that was not performed.

By contributing, you agree that your contribution is licensed under the MIT License.
