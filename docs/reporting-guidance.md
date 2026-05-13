# Reporting Guidance

Phase-specific findings are intentionally granular so evidence can be traced back
to the exact control, URL, and observation that produced it. Final reports should
deduplicate and group related findings into report-ready issues where that makes
the report clearer.

For Phase 2 header findings, use these grouping guidelines:

- `HEADERS-001` through `HEADERS-008` may roll up into `Permissive Content-Security-Policy`.
- `HEADERS-009` through `HEADERS-011` may roll up into `Missing recommended browser security headers`.
- `HEADERS-012` may remain `HSTS max-age below one-year hardening baseline` or be included as a hardening note.
- `HEADERS-013` is a non-finding.
- `HEADERS-014` is informational.

Keep the granular finding IDs in supporting evidence so reviewers can trace each
rolled-up report item back to the raw phase output.
