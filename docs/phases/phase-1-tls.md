# Phase 1: TLS

## Purpose

Phase 1 evaluates the target's TLS posture using available tooling and direct OpenSSL validation while keeping traffic low impact.

## What this phase tests

- Certificate chain verification and expiration.
- TLS protocol negotiation, especially TLS 1.2 and TLS 1.3.
- Direct OpenSSL validation for selected risky cipher claims.
- Optional `testssl`/`testssl.sh` scanner output when available.

## What this phase does not test

- It does not perform broad host discovery.
- It does not test non-web ports unless configured by the phase implementation.
- It does not prove exploitability of every TLS scanner warning.
- It does not authenticate to the application.

## Default command

```bash
./phases/01-tls.sh --workspace assessments/<company>/<target>/<run-id>
```

For approved non-interactive execution:

```bash
./phases/01-tls.sh --workspace assessments/<company>/<target>/<run-id> --yes
```

## Useful options

- `--yes`: run without interactive scope confirmation after approval has been reviewed.
- `--clean`: delete prior Phase 1 evidence before rerunning. Do not use for production evidence unless intentional.
- `-h`, `--help`: print usage.

## Profile/depth controls

TLS checks are mostly fixed because they are lightweight. Profiles may influence timeout or target-selection behavior if implemented later, but the safe default should remain a single approved web endpoint.

## Evidence produced

Evidence is written under:

```text
evidence/phase-1-tls/
status/phase-1-tls.status
```

Expected artifacts include raw `testssl` output when available, OpenSSL command results, certificate details, timestamped evidence files, latest copies, summaries, and `tls-findings.json`.

## Expected results

A modern configuration usually shows:

- Valid certificate chain for the configured hostname.
- Certificate not expired and not close to unexpected expiry.
- TLS 1.2 and TLS 1.3 available.
- No validated support for NULL or anonymous ciphers.
- No contradictory OpenSSL evidence for serious scanner claims.

## How to interpret findings

`testssl` is useful for breadth, while OpenSSL direct checks are useful for confirming specific observations. Some systems install the binary as `testssl`; others use `testssl.sh`. The phase should discover either name when available.

If scanner output suggests NULL or anonymous ciphers, confirm with direct OpenSSL negotiation. Report only the directly validated condition, not the scanner wording alone. Certificate and protocol findings should be tied to concrete command output and timestamps.

## Common false positives/noise

- Scanner heuristics may flag ciphers that cannot actually be negotiated.
- Intermediate devices can present different certificates from different networks.
- Legacy compatibility endpoints may differ from the primary hostname.
- CDN or load-balancer behavior may vary between runs.

## Safety and performance notes

- TLS negotiation checks are low impact.
- `--clean` removes prior TLS evidence for the phase. Prefer a new workspace for official reruns.
- Timestamped evidence is preferred for report citations; `latest` copies are only convenience files.

## Troubleshooting

- Verify the target hostname and SNI value.
- Try both `testssl` and `testssl.sh` command names when checking local tooling.
- Use direct `openssl s_client` commands to verify certificate chain, expiry, protocol, and cipher results.
- Check whether a proxy, CDN, or WAF presents different certificates based on source IP.

## When to increase scope/depth

Increase scope only when additional hostnames, ports, or environments are explicitly authorized. Do not expand TLS testing to unrelated hosts discovered through certificates without approval.
