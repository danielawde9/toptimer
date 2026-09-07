# Task 10 fix round 2

Added a retained close-failure controller with retry/quit paths, and an injected bounded sound catalog whose validation is surfaced inline rather than swallowed. Lifecycle failure remains pending until a later successful close or explicit quit.

Concern: active timer soft-delete has no repository recovery operation; Restore is therefore not shown for an item that has left the bounded active query.
