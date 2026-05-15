# Phase 7: Final Validation

## Purpose

Phase 7 confirms, contradicts, or downgrades likely findings from earlier phases using direct, bounded validation checks. It is not a scanner phase: it does not crawl, fuzz, brute force, authenticate, or perform active exploitation. Its output is designed to de-duplicate Phase 2, ZAP, Nikto, Nmap, Nuclei, and TLS observations into report-friendly validation conclusions.

## Default command

```bash
./phases/07-validation.sh --workspace assessments/<company>/<target>/<run-id> --yes
```

`--workspace <path>` is required. The phase loads `<workspace>/config/target.env`, `<workspace>/config/tool-paths.env` when present, and `config/profiles/<PROFILE>.env` when present. `CURL_BIN` and `OPENSSL_BIN` from `tool-paths.env` are honored when executable; otherwise the script detects `curl` and `openssl` from `PATH`.

## Options

- `--workspace <path>`: Required workspace path.
- `--yes`: Accepted for consistency with other phases and non-interactive operation.
- `--clean`: Removes Phase 7 timestamped raw evidence, latest evidence copies, `validation-summary.md`, and `validation-findings.json` before running.
- `--verbose`: Mirrors additional progress messages to the operator while still preserving the full console log.
- `-h`, `--help`: Prints usage.

## Evidence location

All Phase 7 evidence is written under the selected workspace only:

```text
<workspace>/evidence/phase-7-validation/
```

The status file is written to:

```text
<workspace>/status/phase-7-validation.status
```

The status file includes `STATUS`, `STARTED_UTC`, `FINISHED_UTC`, `EXIT_CODE`, `MESSAGE`, and `PHASE_RUN_ID`.

## Raw evidence files

Each run writes timestamped raw files and updates matching `latest` copies:

- `validation-login-headers-${PHASE_RUN_ID}.txt` and `validation-login-headers-latest.txt`
- `validation-login-body-${PHASE_RUN_ID}.html` and `validation-login-body-latest.html`
- `validation-cors-headers-${PHASE_RUN_ID}.txt` and `validation-cors-headers-latest.txt`
- `validation-base-redirects-${PHASE_RUN_ID}.txt` and `validation-base-redirects-latest.txt`
- `validation-login-redirects-${PHASE_RUN_ID}.txt` and `validation-login-redirects-latest.txt`
- `validation-openssl-tls12-${PHASE_RUN_ID}.txt` and `validation-openssl-tls12-latest.txt`
- `validation-openssl-tls13-${PHASE_RUN_ID}.txt` and `validation-openssl-tls13-latest.txt`
- `validation-openssl-null-anon-${PHASE_RUN_ID}.txt` and `validation-openssl-null-anon-latest.txt`
- `validation-console-${PHASE_RUN_ID}.txt` and `validation-console-latest.txt`

Stable outputs are:

- `validation-summary.md`
- `validation-findings.json`

## Validation logic

### Login headers

Phase 7 captures the final login response from `LOGIN_URL` with `curl -L`, saves the full response headers and body, and extracts report-relevant headers from the final header block:

- `content-security-policy`
- `x-content-type-options`
- `referrer-policy`
- `permissions-policy`
- `strict-transport-security`
- `x-frame-options`
- `cache-control`
- `refresh`
- `access-control-allow-origin`
- `access-control-allow-credentials`
- `vary`

### CSP

Phase 7 validates whether CSP exists on the final login response and checks for grouped CSP weaknesses:

- `script-src` includes `'unsafe-inline'`
- `script-src` includes `'unsafe-eval'`
- `style-src` includes `'unsafe-inline'`
- missing `form-action`
- missing `base-uri`
- missing `object-src`
- broad wildcard sources such as `https://*`
- broad `frame-ancestors`

The grouped `Permissive Content-Security-Policy` finding is `medium/confirmed` when `script-src 'unsafe-inline'`, `script-src 'unsafe-eval'`, or missing `form-action` is directly observed. Additional CSP issues are included as evidence notes so the report has one clear validation-level conclusion instead of many scanner duplicates.

### Browser security headers

The `Missing recommended browser security headers` finding is `low/confirmed` if any of these headers are missing from the final login response:

- `X-Content-Type-Options`
- `Referrer-Policy`
- `Permissions-Policy`

### HSTS

Phase 7 validates HSTS on the final login response:

- Missing HSTS creates a `medium/confirmed` finding.
- Present HSTS with `max-age < 31536000` creates a `low/confirmed` hardening finding.
- Present HSTS meeting the one-year baseline creates an informational good observation.

### Cache controls

Phase 7 validates sensitive-page cache protection on the login response. `no-store`, `private`, `no-cache`, or equivalent `max-age=0` evidence is treated as cache risk not observed. If no equivalent protection is observed, Phase 7 creates a `medium/confirmed` login cache protection finding.

### CORS

Phase 7 sends one direct request to `LOGIN_URL` with:

```text
Origin: https://evil.example
```

It confirms arbitrary origin reflection only when `Access-Control-Allow-Origin` reflects `https://evil.example`. Reflection is `medium/confirmed`; reflection plus `Access-Control-Allow-Credentials: true` is `high/confirmed`. Wildcard plus credentials is also treated as directly confirmed high risk. If reflection is not observed, the phase emits an informational `not_observed` object.

### Redirects and Refresh

Phase 7 captures redirect chains for both `TARGET_BASE_URL` and `LOGIN_URL`, records the final login status, and notes whether a `Refresh` header is present. Redirect-only base response header gaps are context only and are not promoted to confirmed missing-header findings.

### TLS

Phase 7 runs direct OpenSSL checks against `TARGET_HOST:443`:

- TLS 1.2 negotiation
- TLS 1.3 negotiation
- restricted TLS 1.2 `NULL:eNULL:aNULL` negotiation

NULL or anonymous cipher support is `high/confirmed` only if OpenSSL actually negotiates a real NULL or anonymous cipher. If OpenSSL reports `Cipher is (NONE)`, the finding is `informational/not_confirmed`. Modern TLS support is informational when both TLS 1.2 and TLS 1.3 negotiate successfully; direct TLS failures are reported as low/medium only when Phase 7 directly observes the condition.

## Structured findings

`validation-findings.json` contains grouped objects with this schema:

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

The phase intentionally produces grouped findings rather than one item for every scanner observation.

## Summary output

`validation-summary.md` includes:

- target URLs and run ID
- checks performed
- extracted header values
- confirmed findings
- not confirmed / not observed / needs-review findings
- informational observations
- direct evidence file list
- limitations
- a note that scanner outputs are de-duplicated into validation-level conclusions

## How Phase 7 feeds reporting

Report authors should prefer Phase 7 statuses over scanner assumptions. A scanner-only item is not report-confirmed unless Phase 7 directly observes it. If Phase 7 contradicts a scanner result, carry the scanner item as not confirmed or omit it from vulnerability reporting. High findings should appear only when direct Phase 7 evidence validates the high-risk condition.

## Safety and performance notes

- Use targeted, low-volume direct checks only.
- Keep evidence inside the selected workspace.
- Do not broaden scope beyond `TARGET_BASE_URL`, `LOGIN_URL`, and `TARGET_HOST` from workspace configuration.
- Do not add crawling, fuzzing, race testing, brute force, credential stuffing, or intrusive exploitation to this phase.
- Authenticated testing remains placeholder-only until explicit safe handling exists.
