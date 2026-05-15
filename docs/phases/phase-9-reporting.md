# Phase 9: Reporting

## Purpose

Phase 9 normalizes, deduplicates, and packages validated assessment results into report-ready artifacts.

## What this phase tests

Reporting is not a target-testing phase. It tests evidence completeness, finding consistency, deduplication quality, and whether report claims are supported by validation evidence.

## What this phase does not test

- It does not discover new vulnerabilities.
- It does not confirm scanner findings by itself.
- It does not replace Phase 7 validation.
- It does not include scanner non-findings as vulnerabilities.

## Default command

Current reporting entry point:

```bash
./report.sh --workspace assessments/<company>/<target>/<run-id>
```

A future dedicated phase script may write reporting status under `phase-9-reporting`.

## Useful options

`report.sh` currently accepts `--workspace`. Use workspace-level evidence review before generating final report artifacts.

## Profile/depth controls

Profiles should not change final truth. A deeper profile may produce more observations, but only validated and normalized findings should be promoted into the report.

## Evidence produced

Reporting artifacts are written under:

```text
reports/
reports/findings/
```

Expected future artifacts include an executive summary, technical report, evidence index, normalized findings, and an archive manifest or archive package.

## Expected results

A complete reporting phase should produce:

- Executive summary.
- Technical report.
- Evidence index.
- Normalized findings JSON or equivalent structured data.
- Optional encrypted archive or archive manifest.

## How to interpret findings

Report findings should be validated, deduplicated, and written at the right abstraction level. Granular tool observations should be rolled up when they represent one underlying issue.

Example rollups:

- CSP `unsafe-inline`, `unsafe-eval`, and missing `form-action` can roll up into `Permissive Content Security Policy`.
- Missing browser headers can roll up into `Missing Recommended Browser Security Headers`.
- Scanner non-findings stay informational or are omitted.

## Common false positives/noise

- Duplicate missing-header findings from Phase 2, Nmap, Nuclei, and ZAP.
- Scanner severity that does not match validated business impact.
- Informational server banners presented as vulnerabilities.
- Findings that were contradicted by Phase 7 direct checks.

## Safety and performance notes

- Keep reports, archives, raw evidence, and generated workspaces out of Git.
- Redact secrets, tokens, cookies, personal data, and unnecessary sensitive content.
- Encrypt archives according to client or organizational requirements.
- Ensure final wording distinguishes confirmed findings from observations and limitations.

## Troubleshooting

- If a finding lacks evidence, return to Phase 7 validation before reporting it.
- If multiple tools report the same issue, select the clearest direct evidence and deduplicate.
- If generated report data is empty, confirm parser outputs and normalized findings paths.
- If an issue is real but low impact, adjust severity and narrative rather than omitting important context.

## When to increase scope/depth

Do not increase scanning depth during reporting. If reporting identifies evidence gaps, run targeted Phase 7 validation or an approved phase rerun in a new workspace or with documented evidence handling.
