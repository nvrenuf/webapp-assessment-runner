# Phase 8: Authenticated Testing

## Purpose

Phase 8 is planned authenticated testing for authorized application behavior, session handling, and access control. Current repository behavior is placeholder-only.

## What this phase tests

When implemented and authorized, authenticated testing may cover:

- Session cookies and cookie attributes.
- CSRF protections.
- Authorization checks.
- IDOR and tenant isolation.
- API routes reachable only after login.
- Workflow abuse cases.
- XSS checks where explicitly authorized.
- File upload behavior where explicitly authorized.
- Logout and session invalidation.

## What this phase does not test

- It does not use real credentials without explicit authorization.
- It does not store credentials in Git.
- It does not perform destructive workflow abuse.
- It does not test cross-tenant access unless at least two approved users/tenants are provided.
- It does not bypass scope restrictions.

## Default command

Current placeholder behavior:

```bash
./phases/08-authenticated-placeholder.sh --workspace assessments/<company>/<target>/<run-id>
```

## Useful options

The placeholder accepts `--workspace`. A future implementation should support explicit scope confirmation and safe secret handling before accepting options that launch authenticated traffic.

## Profile/depth controls

Profiles should not silently enable authenticated testing. The operator needs explicit authorization, a test plan, and test accounts. For IDOR or tenant-isolation testing, at least two users or tenants are needed so access-control boundaries can be tested safely.

## Evidence produced

Evidence is written under:

```text
evidence/phase-8-authenticated/
status/phase-8-authenticated.status
```

Future evidence may include sanitized request/response captures, workflow notes, API route inventories, validation output, and redacted screenshots. Credentials, cookies, session files, and HAR files containing secrets must not be committed to Git.

## Expected results

Current placeholder runs should be marked skipped or completed without credential use. Implemented authenticated tests should produce carefully scoped observations and direct evidence for validated findings.

## How to interpret findings

Authenticated findings require context: user role, tenant, route, request method, expected authorization boundary, observed behavior, and business impact. Findings such as IDOR must be confirmed by showing that one test identity can access another identity's unauthorized data or action within approved scope.

## Common false positives/noise

- Test accounts with intentionally broad permissions.
- Shared demo data that is not tenant-specific.
- CSRF checks that miss same-site cookie behavior or framework-specific tokens.
- Session behavior affected by SSO or upstream identity provider policy.

## Safety and performance notes

- Authenticated testing needs dedicated test accounts and explicit authorization.
- Use an `auth.env` file with placeholders for planning, but never commit real secrets.
- Do not print credentials, cookies, or tokens to logs.
- Coordinate tests that create, modify, or delete data.
- Use staging when production workflow side effects are not acceptable.

## Troubleshooting

- Confirm account roles, tenant relationships, and expected permissions with the target owner.
- Verify that credentials are loaded from an approved local secret source and not Git.
- Reproduce authorization issues with two distinct sessions where required.
- Redact sensitive data before sharing evidence.

## When to increase scope/depth

Increase authenticated depth only after approving specific workflows, roles, tenants, and side-effect boundaries. Add users/tenants when access-control questions cannot be answered with a single account.
