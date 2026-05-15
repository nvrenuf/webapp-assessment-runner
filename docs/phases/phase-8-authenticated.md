# Phase 8: Authenticated Testing Scaffold

## Purpose

Phase 8 prepares a workspace for future authenticated testing without performing authenticated testing yet. The implemented phase validates the workspace, reads authenticated-testing intent from `config/target.env`, inspects `config/auth.env` when present, creates sanitized readiness/checklist/summary outputs, and writes a Phase 8 status file.

This phase is scaffold-only. It does **not** authenticate to the target, submit forms, crawl, fuzz, brute force, call APIs with credentials, test IDOR, test tenant isolation, or run active authenticated checks.

## Command

```bash
./phases/08-authenticated.sh --workspace assessments/<company>/<target>/<run-id> [--yes] [--clean] [--verbose]
```

The compatibility wrapper remains available:

```bash
./phases/08-authenticated-placeholder.sh --workspace assessments/<company>/<target>/<run-id>
```

## Options

- `--workspace <path>`: Required. Selects the assessment workspace.
- `--yes`: Accepted for consistency with other phases. The scaffold is non-interactive.
- `--clean`: Removes Phase 8 timestamped evidence, latest evidence, `authenticated-summary.md`, and `authenticated-findings.json` before running.
- `--verbose`: Mirrors additional operational details to the console log while still avoiding secret values.

## Configuration loaded

Phase 8 validates the workspace and loads:

- `<workspace>/config/target.env` for `TARGET_BASE_URL`, `PROFILE`, `AUTH_MODE`, and `AUTH_ENABLED`.
- `<workspace>/config/tool-paths.env` if present, for consistency with other phases.
- `config/profiles/<PROFILE>.env` if present, for profile context.
- `<workspace>/config/auth.env` if present, by parsing placeholder variables for readiness and secret-safety checks.

## Auth mode behavior

Phase 8 uses `AUTH_MODE` and `AUTH_ENABLED` from `target.env`:

- `AUTH_MODE=none` or `AUTH_ENABLED=false` produces readiness `not_enabled`, exits successfully, and records an informational finding titled `Authenticated testing not enabled`.
- `AUTH_MODE=placeholder` or `AUTH_ENABLED=true` expects `<workspace>/config/auth.env` to exist.
- If authenticated testing is enabled but `auth.env` is missing, readiness is `missing_auth_env` and the phase records a low-severity `needs_input` finding.
- If `auth.env` exists and only placeholder values are detected, readiness is `placeholder_ready` and the phase records an informational scaffold-ready finding.
- If possible real secret material is detected, readiness is `unsafe_secret_detected`; evidence lists variable names only, never values. Explicit non-placeholder password/token/cookie/session/JWT/API-key variables fail the phase after writing sanitized outputs, while less certain high-entropy values warn by default.

## Supported `auth.env` placeholder keys

`auth.env` must remain placeholder-only. Phase 8 supports and documents these planning keys:

```bash
AUTH_LOGIN_METHOD="manual|cookie|header|browser|future"
AUTH_USERNAME_PLACEHOLDER="required"
AUTH_PASSWORD_PLACEHOLDER="required"
AUTH_TEST_USER_1="placeholder"
AUTH_TEST_USER_2="placeholder"
AUTH_TEST_TENANT_1="placeholder"
AUTH_TEST_TENANT_2="placeholder"
AUTH_SESSION_COOKIE_PLACEHOLDER="placeholder"
AUTH_CSRF_TOKEN_PLACEHOLDER="placeholder"
AUTH_BEARER_TOKEN_PLACEHOLDER="placeholder"
AUTH_NOTES="placeholder only; do not store real secrets"
```

Not every key is required for a successful scaffold run. Missing placeholder keys are reported as planning warnings, not as confirmed vulnerabilities. Future IDOR and tenant-isolation checks require at least two users and two tenants, so missing second-user or second-tenant placeholders are called out as prerequisites.

## Evidence produced

Evidence is written only under the selected workspace:

```text
evidence/phase-8-authenticated/
```

Timestamped files:

- `auth-readiness-${PHASE_RUN_ID}.json`
- `auth-checklist-${PHASE_RUN_ID}.md`
- `auth-notes-${PHASE_RUN_ID}.md`
- `auth-console-${PHASE_RUN_ID}.txt`

Latest copies:

- `auth-readiness-latest.json`
- `auth-checklist-latest.md`
- `auth-notes-latest.md`
- `auth-console-latest.txt`

Stable outputs:

- `authenticated-summary.md`
- `authenticated-findings.json`

Status is written to:

```text
status/phase-8-authenticated.status
```

The status file includes `STATUS`, `STARTED_UTC`, `FINISHED_UTC`, `EXIT_CODE`, `MESSAGE`, `PHASE_RUN_ID`, `AUTH_MODE`, `AUTH_ENABLED`, and `AUTH_READINESS`.

## Finding behavior

Phase 8 creates one scaffold finding using the authenticated finding schema:

- Auth not enabled: `Authenticated testing not enabled`, informational, `not_enabled`.
- Auth enabled but missing `auth.env`: `Authenticated testing configuration missing`, low, `needs_input`.
- Placeholder scaffold ready: `Authenticated testing scaffold ready`, informational, `observed`.
- Unsafe secret detected: `Possible real secret stored in auth config`, medium, `observed`; evidence lists variable names only.

Phase 8 does not create high-severity findings in scaffold mode.

## Checklist sections

The generated checklist includes:

- Required authorization
- Required test accounts
- Minimum account model
- Session handling
- CSRF handling
- IDOR checks
- Tenant isolation checks
- Role/permission checks
- API route inventory
- File upload/download checks, if authorized
- Logout/session invalidation
- Evidence handling
- What must not be stored in Git
- Future automation notes

## Minimum account model

Future authenticated testing requires:

- One normal test user for basic authenticated checks.
- Two users in the same tenant for horizontal authorization checks.
- Two users in different tenants for tenant isolation checks.
- At least one lower-privilege and one higher-privilege role for vertical authorization checks.
- Explicit written approval before testing destructive workflows.

## Safety limits

Phase 8 must not:

- Authenticate.
- Submit forms.
- Crawl.
- Call APIs using credentials.
- Store real credentials.
- Print secrets.
- Write evidence outside the selected workspace.
- Run brute force, denial of service, race testing, fuzzing, credential stuffing, intrusive checks, IDOR tests, tenant-isolation tests, or active authenticated checks.

## Future authenticated testing plan

Future work should add explicit approval gates, safe local secret loading, redaction, browser/session isolation, route inventory controls, and narrowly scoped low-impact checks. Real credential handling should be implemented only after the repository has safe storage/loading conventions that avoid Git, logs, status files, summaries, JSON evidence, command history, and generated reports.
