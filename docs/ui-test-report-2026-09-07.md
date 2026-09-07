# TopTimer UI test report — 2026-09-07

## Fixed production blocker

The installed app previously showed a timer status item but an empty, oversized
popover. The evidence was the user capture at
`/var/folders/pg/nsxb6z4d2l70w6jybph_gnq40000gn/T/codex-clipboard-8b119da8-35ba-4926-a647-8a818374dada.png`.

`StatusBarController.open()` now assigns a concrete 276 by 110 content size to
both `NSPopover` and `NSHostingController`, and frames the SwiftUI root to that
same size. This removes the former zero-by-zero hosting surface.

## Automated verification

- `StatusBarPopoverPresentationTests` first failed with popover content size
  `(0, 0)` and a content view with zero width and height. It now proves the real
  production status-bar controller installs a 276 by 110 non-empty content
  surface containing the accessible Quick Entry field.
- `QuickEntryNativeRoutingTests` covers Return, Escape, suggestions, Space,
  IME composition and focus retention through native field-editor callbacks.
- Full `swift test`: 270 tests, 0 failures.
- Release build with warnings treated as errors: passed.
- Package-safety and installed-bundle verification: passed.

## Installed build

`/Applications/TopTimer.app` was replaced with the verified current bundle and
launched. The previous bundle is recoverable in Trash as
`TopTimer-before-popover-fix-20260907-2014.app`.

## Remaining live verification boundary

The native UI automation service timed out while attaching to the installed
TopTimer process after the reinstall, so this report does not represent the
automated component tests as proof of a visible menu-bar click. The next live
check is to click the hourglass in the menu bar and confirm the compact Quick
Entry panel has the input and four toolbar buttons. A fresh screenshot of that
popover is sufficient to compare against the fixed layout if automation remains
unavailable.
