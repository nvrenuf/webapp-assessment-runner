# Authenticated Testing Plan

Authenticated testing is placeholder-only in this foundation.

Use `--auth none` for unauthenticated testing. Use `--auth placeholder` to create an authenticated testing scaffold. The aliases `--auth no` and `--auth yes` are accepted for convenience.

Before implementation, add:

- Written authorization for authenticated testing.
- Explicit account role, data handling, and lockout constraints.
- Secret handling that avoids console output and logs.
- Cookie, session, and HAR storage only inside workspaces.
- Passive browser-driven collection before any active authenticated checks.
- Clear manual validation steps for scanner findings.
