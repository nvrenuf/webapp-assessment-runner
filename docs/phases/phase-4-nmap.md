# Phase 4: Nmap

## Purpose

Phase 4 performs low-impact web service validation with Nmap against approved web ports.

## What this phase tests

- Whether the configured web service ports are reachable.
- Basic service and TLS/header script observations as implemented by the phase.
- Profile-controlled port list and pacing.

## What this phase does not test

- It does not run `-A` aggressive scanning.
- It does not run UDP scans.
- It does not run all-port scans.
- It does not perform broad network discovery.
- It does not prove that header observations are unique findings.

## Default command

```bash
./phases/04-nmap.sh --workspace assessments/<company>/<target>/<run-id>
```

## Useful options

- `--yes`: run non-interactively after scope approval.
- `--clean`: delete prior Phase 4 evidence before rerunning.
- `--verbose`: print command and monitoring details.
- `-h`, `--help`: print usage.

## Profile/depth controls

Default Nmap scope is narrow:

- `safe`: port `443` only.
- `balanced`: port `443` only.
- `deep`: ports `80,443` when explicitly selected.
- `maintenance`: ports `80,443` with a faster approved maintenance profile.

Broader discovery is a separate explicitly scoped activity, not a default phase behavior.

## Evidence produced

Evidence is written under:

```text
evidence/phase-4-nmap/
status/phase-4-nmap.status
```

Artifacts typically include timestamped Nmap normal/XML or grepable output as implemented, console logs, summary files, latest copies, and `nmap-findings.json`.

## Expected results

Expected production results often show only approved web ports reachable and basic service metadata. Header observations may duplicate Phase 2 and should be deduplicated later.

## How to interpret findings

Treat AWS ELB, load-balancer, CDN, or generic `Server` header observations as informational unless they expose a concrete, validated risk. Missing-header script results may duplicate Phase 2; use Phase 2 response captures as the primary browser-header evidence.

## Common false positives/noise

- Load balancers report generic service fingerprints.
- CDN or WAF behavior changes Nmap service detection.
- Nmap HTTP scripts report missing headers on redirects or non-HTML responses.
- Server headers identify infrastructure but not necessarily a vulnerability.

## Safety and performance notes

- No `-A`, UDP, or all-port scans by default.
- Default `443` scope minimizes target impact.
- Use profile pacing values and avoid manual command expansion unless explicitly approved.

## Troubleshooting

- Confirm `TARGET_HOST` resolves from the assessment network.
- Review profile values for `NMAP_PORTS`, `NMAP_MAX_RATE`, `NMAP_SCAN_DELAY`, and `NMAP_MAX_RETRIES`.
- Validate unexpected service results with direct `curl` or `openssl` checks.
- If the phase fails, review Nmap output and status files before rerunning with `--clean`.

## When to increase scope/depth

Increase to `80,443` only when both web ports are in scope. Any broad discovery, non-web port validation, UDP scanning, or aggressive version detection must be a separate approved activity.
