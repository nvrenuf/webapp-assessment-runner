# Phase 7: Final Validation

## Purpose

Phase 7 confirms, contradicts, or downgrades findings from earlier phases using direct, reproducible checks. This phase is the source of truth for report status.

## What this phase tests

- Direct `curl` validation of headers, redirects, CSP, CORS, and response behavior.
- Direct OpenSSL validation of TLS and certificate claims.
- Reproduction checks for scanner observations selected for report consideration.
- Evidence quality and consistency across phases.

## What this phase does not test

- It does not automatically prove every scanner observation.
- It does not broaden target scope.
- It does not perform intrusive exploitation.
- It does not replace authenticated testing for findings that require an authenticated context.

## Default command

Current placeholder behavior:

```bash
./phases/07-validation.sh --workspace assessments/<company>/<target>/<run-id>
```

## Useful options

The current placeholder accepts `--workspace`. Future validation implementations may support `--yes`, `--clean`, and `--verbose`.

Use `--clean` carefully: validation evidence is usually the evidence most directly tied to final report decisions.

## Profile/depth controls

Validation should be finding-driven rather than scanner-depth-driven. Profiles may control pacing, but the main input should be the set of candidate findings that need confirmation.

## Evidence produced

Evidence is written under:

```text
evidence/phase-7-validation/
status/phase-7-validation.status
```

Planned artifacts include direct command transcripts, HTTP request/response captures, OpenSSL output, validation notes, and final status decisions for each candidate finding.

## Expected results

Each candidate finding should be classified as confirmed, not confirmed, informational, duplicate, accepted limitation, or needs more evidence. Scanner-only or contradicted items should be marked not confirmed rather than carried into the report as vulnerabilities.

## How to interpret findings

Phase 7 decisions should override scanner assumptions. If direct curl/OpenSSL evidence contradicts a scanner, the scanner item is not confirmed. If the evidence confirms the condition but impact is limited, severity and report wording should reflect the validated impact.

## Common false positives/noise

- Scanner findings based on redirects instead of final content.
- Header findings duplicated across multiple tools.
- TLS warnings that cannot be negotiated with OpenSSL.
- CORS observations on unauthenticated pages that do not expose authenticated APIs.

## Safety and performance notes

- Use targeted, low-volume direct checks.
- Do not turn validation into fuzzing or exploitation.
- Keep commands reproducible and include timestamps where possible.
- Preserve validation evidence; avoid `--clean` unless intentionally replacing a failed validation attempt.

## Troubleshooting

- Start from the raw evidence path for each candidate finding.
- Reproduce with the simplest direct command possible.
- Capture both positive and negative evidence.
- If behavior is inconsistent, document source IP, time, redirect chain, headers, and any CDN/WAF indicators.

## When to increase scope/depth

Increase validation depth only to answer a specific report question, such as whether a header is missing on final HTML routes or whether a TLS cipher can actually negotiate. Do not use validation to discover unrelated issues without approval.
