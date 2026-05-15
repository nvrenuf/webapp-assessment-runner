# Phase 6: ZAP Passive

## Purpose

Phase 6 is planned passive-only OWASP ZAP coverage for browser/proxy-assisted discovery and passive alert collection.

## What this phase tests

- Passive observations from traffic sent through ZAP.
- Limited spider output when explicitly enabled by the planned implementation.
- Passive scan alerts and report exports.
- Coverage gaps that static curl-based phases may miss.

## What this phase does not test

- It does not run active scanning by default.
- It does not fuzz forms, attack parameters, or force browse.
- It does not authenticate unless an approved authenticated workflow is provided.
- It does not replace direct Phase 7 validation.

## Default command

Current placeholder behavior:

```bash
./phases/06-zap-passive.sh --workspace assessments/<company>/<target>/<run-id>
```

Future implementations should preserve passive-only defaults.

## Useful options

The current placeholder accepts `--workspace`. Future options may include `--yes`, `--clean`, and `--verbose` if passive ZAP evidence is generated.

- `--yes`: should be used only after scope confirmation.
- `--clean`: should delete only prior Phase 6 evidence and should be avoided for production evidence unless intentional.
- `--verbose`: should print ZAP daemon, API, spider, passive-scan, and export progress.

## Profile/depth controls

Safe defaults should use limited spidering and passive scanning only. Deeper profiles may increase passive crawl limits or include more in-scope URLs, but active scan must remain disabled unless there is explicit authorization and a maintenance window.

## Evidence produced

Current placeholder evidence is written under:

```text
evidence/phase-6-zap/
status/phase-6-zap.status
```

Planned artifacts include ZAP passive alerts, exported reports, spider URL lists, API export JSON, and proxy session metadata that excludes credentials and secrets.

## Expected results

For the placeholder, a completed status means no passive proxy activity was launched. For the planned implementation, expected results include passive alerts that require triage and a record of visited URLs.

## How to interpret findings

ZAP passive alerts are observations. Validate material alerts in Phase 7 before reporting. Passive alerts often identify missing headers, cookie attributes, caching behavior, or CSP concerns that may duplicate earlier phases.

## Common false positives/noise

- Passive alerts on redirects or static assets.
- Duplicate missing-header alerts already captured in Phase 2.
- Cookie alerts on non-sensitive unauthenticated responses.
- Spider-discovered URLs that are out of scope or non-canonical.

## Safety and performance notes

- Use ZAP daemon API instead of relying on `zap-baseline.py` so behavior, limits, and exports are explicit.
- Keep spidering limited.
- No active scan by default.
- Active scan requires explicit written authorization, an agreed maintenance window, and clear target limits.

## Troubleshooting

- Confirm ZAP is installed as `zaproxy`, `/usr/share/zaproxy/zap.sh`, or `owasp-zap`.
- Check daemon startup logs and API reachability.
- Ensure proxy settings do not leak traffic outside the approved target.
- If passive scans do not complete, review queued records and export partial alerts with clear limitations.

## When to increase scope/depth

Increase passive crawl depth when the target owner approves additional traffic and the operator needs coverage beyond base/login responses. Do not switch to active scan as a profile-depth change; treat it as a separate authorized activity.
