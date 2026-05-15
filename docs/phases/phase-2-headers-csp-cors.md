# Phase 2: Headers, CSP, and CORS

## Purpose

Phase 2 captures HTTP response evidence and analyzes browser security headers, Content Security Policy, redirects, and basic CORS behavior.

## What this phase tests

- Base URL response headers, bodies, and redirects.
- Login URL response headers, bodies, and redirects.
- Presence and quality of browser security headers.
- CSP directives such as `script-src`, `object-src`, `base-uri`, and `form-action`.
- Whether an arbitrary `Origin` is reflected in CORS headers on unauthenticated base or login responses.

## What this phase does not test

- It does not fully validate authenticated API CORS behavior.
- It does not execute JavaScript in a browser.
- It does not exploit XSS or clickjacking.
- It does not crawl the site or inspect every route.
- It does not confirm that a scanner-style header issue is exploitable.

## Default command

```bash
./phases/02-headers.sh --workspace assessments/<company>/<target>/<run-id>
```

## Useful options

- `--yes`: run non-interactively after scope approval.
- `--clean`: delete prior Phase 2 evidence before rerunning. Avoid during production evidence collection unless intentional.
- `-h`, `--help`: print usage.

## Profile/depth controls

Header checks are intentionally narrow by default: base URL and login URL. Deeper coverage should be added only through approved target lists, authenticated API coverage, or browser-assisted passive testing.

## Evidence produced

Evidence is written under:

```text
evidence/phase-2-headers/
status/phase-2-headers.status
```

Artifacts typically include captured request/response headers, response bodies, redirect traces, CORS test responses, a summary, and `headers-findings.json`.

## Expected results

Good results commonly include:

- HTTPS redirects behaving as expected.
- Sensitive browser headers present on final HTML responses.
- CSP avoiding `unsafe-inline` and `unsafe-eval` where practical.
- CSP including important directives such as `form-action`.
- No arbitrary-origin CORS reflection on unauthenticated responses.

## How to interpret findings

Do not over-report missing headers on redirect-only base responses. Evaluate the final response that serves meaningful HTML or application content. Expected reportable items may include CSP `unsafe-inline`, CSP `unsafe-eval`, missing CSP `form-action`, and missing recommended browser security headers.

CORS reflection on the login page can be a useful signal, but it is not enough to validate authenticated API CORS risk. Authenticated API CORS needs Phase 8-style authenticated requests and explicit authorization.

## Common false positives/noise

- Redirect responses may intentionally have fewer headers than final content responses.
- Static assets may not need every browser security header expected on HTML.
- CSP may be intentionally transitional during a migration.
- CORS on unauthenticated pages may not expose credentials or sensitive data.
- Nmap or Nuclei may duplicate missing-header observations from this phase.

## Safety and performance notes

- Sends a small number of HTTP requests.
- Does not crawl or fuzz.
- Stores response bodies as evidence; review for sensitive content before sharing or archiving.

## Troubleshooting

- Confirm `TARGET_BASE_URL` and `LOGIN_URL` in `config/target.env`.
- Inspect redirect evidence to identify the final response that should be assessed.
- Compare `curl -I` and full `curl -D` captures if header behavior appears inconsistent.
- Check whether CDN/WAF rules vary by user agent or source network.

## When to increase scope/depth

Increase coverage when additional important routes, sub-applications, or authenticated APIs are approved. Use browser/ZAP passive testing or Phase 8 authenticated checks rather than treating login-page CORS as proof of API exposure.
