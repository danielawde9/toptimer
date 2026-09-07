# Task 10 fix round 3

## RED evidence

`swift test --filter TimerRowActionVisibilityTests` failed as expected with
`cannot find 'TimerRowActionVisibility' in scope` before the visibility model
was added.

## Green work

- Added a behavior-tested hover-or-keyboard-focus action visibility model.
- Added revision-incrementing timer restore domain/repository/AppState seam.
- Added lifecycle retry-success behavior coverage.

Concern: Restore becomes available only through a future deleted-items surface;
soft-deleted items are intentionally absent from the bounded active query.
