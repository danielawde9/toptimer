# Decisions ledger

This ledger is append-only. Later changes supersede earlier entries rather than
rewriting history.

## 2026-09-04 — Native macOS implementation

**Decision:** Build TopTimer with SwiftUI and small AppKit integration points,
targeting macOS 13.5 and later.

**Why:** A native implementation provides the smallest installed footprint and
the most reliable access to menu-bar, notification, login-item, keyboard
shortcut, and power-management APIs.

**If the client answers differently:** A cross-platform requirement would need a
new architecture decision and separate Windows/Linux interface designs.

## 2026-09-04 — Original identity with functional parity

**Decision:** Match the publicly documented timer capabilities and efficient
workflow of Horo without using its name, source, icon, artwork, or pixel-for-pixel
interface. The product name is TopTimer.

**Why:** The requested functionality is useful, while an original identity keeps
the open-source project maintainable and avoids confusing it with the existing
commercial product.

**If the client answers differently:** Supplied, licensed brand assets can replace
TopTimer assets after their rights and permitted uses are documented.

## 2026-09-04 — Local-only data

**Decision:** Store timers, presets, settings, and history locally with Core Data.
The app has no account, analytics, telemetry, or network feature.

**Why:** Timer data does not require a service, and local-only storage preserves
privacy and offline reliability.

**If the client answers differently:** Sync would require a separate privacy,
conflict-resolution, and service-availability design.

## 2026-09-04 — Free open-source release

**Decision:** Ship all implemented features without a paid tier under the MIT
license.

**Why:** The client requested an open-source repository and will connect the local
Git repository to GitHub later.

**If the client answers differently:** A license change must happen before public
distribution and may require contributor consent after outside contributions.

## 2026-09-04 — Recurrence and menu-bar priority

**Decision:** Recurrence is chosen per timer: none, interval, daily, weekdays,
weekly, or selected weekdays. With multiple active countdowns, the menu bar shows
the one due soonest; clicking it reveals every timer and stopwatch.

**Why:** This keeps the menu bar compact while preserving direct access to all
running work. Explicit recurrence prevents accidental repeating alerts.

**If the client answers differently:** Menu-bar selection can become a configurable
preference, and additional recurrence rules can be added without changing saved
timer identity.
