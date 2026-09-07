# Task 10 fix round 1

Completed the list and lifecycle corrections in this round:

- unacknowledged completed timers remain in the bounded active list;
- rows omit descriptions and include live remaining/end-time plus recurrence text;
- quick-entry toolbar now has icon-only Settings, Run, List, and Quit controls with 28-point targets;
- termination close failures remain pending until the explicit quit effect.

Verification: focused lifecycle test and full suite plus strict debug/release builds were run in this session.

Concern: imported sound catalog injection and a retry UI wired to a failed store-close completion require a separate application-controller seam; the editor currently exposes its persisted selected sound only.
