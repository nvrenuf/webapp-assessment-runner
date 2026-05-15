# Phase 7: Final Validation

## Purpose

Phase 7 confirms, contradicts, or downgrades findings from earlier phases using direct, reproducible checks. This phase is the source of truth for final report status.

Phase 7 is intentionally not another scanner phase. It uses targeted `curl` and OpenSSL checks to decide which previously observed issues are actually confirmed, which are duplicates, and which are not confirmed.

## What this phase tests

- Final login-page HTTP headers and response behavior.
- Content Security Policy weaknesses directly visible on `LOGIN_URL`.
- Missing recommended browser security headers on the final meaningful HTML response.
- HSTS presence and `max-age` value.
- Cache-control behavior for the login page.
- Basic unauthenticated CORS arbitrary-origin reflection.
- Base and login redirect chains.
- Direct TLS 1.2 and TLS 1.3 negotiation with OpenSSL.
- Direct NULL/anonymous cipher validation with OpenSSL when earlier tools produced related observations.
- Evidence consistency across earlier phases.

## What this phase does not test

- It does not crawl the application.
- It does not fuzz, brute force, exploit, or authenticate.
- It does not run active scanners.
- It does not broaden target scope beyond configured base/login targets.
- It does not validate authenticated API CORS or authorization behavior.
- It does not automatically prove every scanner observation.

Authenticated findings need Phase 8. Reporting rollups and final narrative happen in Phase 9.

## Default command

```bash
./phases/07-validation.sh --workspace assessments/<company>/<target>/<run-id> --yes --verbose
```

For a clean test rerun only:

```bash
./phases/07-validation.sh --workspace assessments/<company>/<target>/<run-id> --yes --clean --verbose
```

Avoid `--clean` for production evidence unless intentionally replacing Phase 7 validation evidence.

## Useful options

- `--workspace <path>`: required workspace path.
- `--yes`: run non-interactively after scope approval.
- `--clean`: delete prior Phase 7 validation evidence before rerunning.
- `--verbose`: print validation progress and output locations.
- `-h`, `--help`: print usage.

## Configuration loaded

The phase should load these files in order:

1. `<workspace>/config/target.env`
2. `<workspace>/config/tool-paths.env`, when present
3. `config/profiles/<PROFILE>.env`, when present

Required target values include:

- `TARGET_BASE_URL`
- `LOGIN_URL`
- `TARGET_HOST`
- `PROFILE`

Tool paths may be supplied by preflight through:

- `CURL_BIN`
- `OPENSSL_BIN`

If those are absent, the phase should detect `curl` and `openssl` from `PATH`.

## Implemented validation workflow

The intended Phase 7 workflow is:

1. Capture final headers and body from `LOGIN_URL`.
2. Capture redirect chains for `TARGET_BASE_URL` and `LOGIN_URL`.
3. Send a single CORS validation request to `LOGIN_URL` with `Origin: https://evil.example`.
4. Parse and validate CSP directives from the final login response.
5. Confirm missing browser security headers on the final login response.
6. Confirm HSTS presence and whether `max-age` meets a one-year hardening baseline.
7. Confirm login-page cache protection, especially `no-store`.
8. Run OpenSSL TLS 1.2 and TLS 1.3 negotiation checks.
9. Run restricted OpenSSL NULL/aNULL/eNULL validation.
10. Produce grouped, report-friendly validation findings.

Phase 7 should not generate a separate final finding for every scanner observation. It should group related issues into report-level conclusions.

## Evidence produced

Evidence is written under:

```text
<workspace>/evidence/phase-7-validation/
```

Expected timestamped raw artifacts:

- `validation-login-headers-<run-id>.txt`
- `validation-login-body-<run-id>.html`
- `validation-cors-headers-<run-id>.txt`
- `validation-base-redirects-<run-id>.txt`
- `validation-login-redirects-<run-id>.txt`
- `validation-openssl-tls12-<run-id>.txt`
- `validation-openssl-tls13-<run-id>.txt`
- `validation-openssl-null-anon-<run-id>.txt`
- `validation-console-<run-id>.txt`

Expected latest copies:

- `validation-login-headers-latest.txt`
- `validation-login-body-latest.html`
- `validation-cors-headers-latest.txt`
- `validation-base-redirects-latest.txt`
- `validation-login-redirects-latest.txt`
- `validation-openssl-tls12-latest.txt`
- `validation-openssl-tls13-latest.txt`
- `validation-openssl-null-anon-latest.txt`
- `validation-console-latest.txt`

Stable outputs:

- `validation-summary.md`
- `validation-findings.json`

Status files:

- `<workspace>/status/phase-7-validation.status`
- `<workspace>/status/phase-7-validation.json`, if shared status writing is enabled

## Expected validation findings

Phase 7 should produce grouped findings such as:

### Permissive Content-Security-Policy

Confirmed when the final login-page CSP directly shows material weaknesses, such as:

- `script-src` includes `'unsafe-inline'`
- `script-src` includes `'unsafe-eval'`
- `form-action` is missing

Recommended remediation should include removing `unsafe-eval`, replacing `unsafe-inline` with nonces or hashes where practical, adding `form-action 'self'`, adding `base-uri 'self'`, and adding `object-src 'none'`.

### Missing recommended browser security headers

Confirmed when the final login response is missing one or more of:

- `X-Content-Type-Options`
- `Referrer-Policy`
- `Permissions-Policy`

Recommended remediation should include `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, and a restrictive `Permissions-Policy` baseline.

### HSTS max-age below hardening baseline

Confirmed as low severity when HSTS is present but `max-age` is below `31536000`. If HSTS is missing entirely on the final login response, that is stronger evidence than a low hardening gap and should be treated separately.

### CORS arbitrary origin reflection

Confirmed only when direct validation shows the arbitrary origin is reflected. If reflection or wildcard origin is combined with `Access-Control-Allow-Credentials: true`, severity should increase. If not observed, record as informational or `not_observed`, not as a vulnerability.

### Login cache protection

If `Cache-Control` includes `no-store` or equivalent sensitive-page protection, cache risk should be `not_observed` or omitted. Do not report cache risk when direct validation confirms `no-store`.

### NULL/anonymous cipher support

Confirmed only if OpenSSL actually negotiates a NULL or anonymous cipher. If OpenSSL output says `Cipher is (NONE)`, the scanner observation is not confirmed.

### TLS modern protocol support

Informational when TLS 1.2 and TLS 1.3 both negotiate successfully. Do not convert successful modern TLS negotiation into a vulnerability.

### Redirect behavior

Base URL redirects should be documented as informational. Do not report missing browser headers on redirect-only base responses when the final login response is the meaningful content response.

## Finding schema

`validation-findings.json` should contain grouped findings using this schema:

```json
{
  "id": "VALIDATION-001",
  "title": "...",
  "severity": "high|medium|low|informational",
  "status": "confirmed|not_confirmed|not_observed|observed|needs_review|informational",
  "source": "phase-7-validation",
  "category": "headers|csp|cors|tls|cache|redirect|misc",
  "url": "...",
  "evidence": "...",
  "description": "...",
  "recommendation": "..."
}
```

## How to interpret findings

Phase 7 decisions should override scanner assumptions. If direct `curl` or OpenSSL evidence contradicts a scanner, the scanner item is not confirmed. If evidence confirms the condition but impact is limited, severity and report wording should reflect the validated impact.

The output should be more report-friendly than scanner output. For example:

- Multiple CSP scanner alerts should roll up into `Permissive Content-Security-Policy`.
- Missing header observations should roll up into `Missing recommended browser security headers`.
- CORS non-reflection should be a non-finding.
- TLS NULL/anonymous claims should be confirmed only through OpenSSL negotiation.

## Common false positives/noise

- Scanner findings based on redirect responses instead of final content.
- Header findings duplicated across Phase 2, Nikto, Nmap, Nuclei, and ZAP.
- TLS warnings that cannot be negotiated with OpenSSL.
- CORS observations on unauthenticated pages that do not expose authenticated APIs.
- ZAP and Nuclei CSP findings that describe the same underlying CSP policy weakness.

## Safety and performance notes

- Use targeted, low-volume direct checks.
- Do not turn validation into crawling, fuzzing, exploitation, or active scanning.
- Keep commands reproducible and store raw outputs.
- Preserve validation evidence; avoid `--clean` unless intentionally replacing a failed validation attempt.
- Phase 7 evidence is likely to be cited directly in the final report, so treat it as high-value evidence.

## Troubleshooting

- Confirm `TARGET_BASE_URL`, `LOGIN_URL`, and `TARGET_HOST` in `config/target.env`.
- Review `validation-console-latest.txt` for command failures.
- Compare Phase 7 headers with Phase 2 `*-headers-latest.txt` if behavior changed.
- If TLS behavior is inconsistent, confirm SNI and source network.
- If `curl` output differs from browser or ZAP output, check redirects, CDN/WAF behavior, and response variance by user agent.
- If a finding appears only in scanner output and not in Phase 7, mark it not confirmed unless there is a specific reason to retain it.

## When to increase scope/depth

Increase validation depth only to answer a specific report question, such as:

- whether the same missing header exists on another final HTML route,
- whether a CSP issue affects authenticated application pages,
- whether an API endpoint reflects arbitrary CORS origins,
- whether a TLS issue appears on another explicitly authorized hostname or port.

Do not use Phase 7 to discover unrelated issues. Additional validation targets require explicit scope approval or should move into authenticated Phase 8.