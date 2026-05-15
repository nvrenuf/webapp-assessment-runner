# Phase 5: Nuclei

## Purpose

Phase 5 runs a low-rate Nuclei misconfiguration scan against the approved base URL using constrained tags and excluded intrusive categories.

## What this phase tests

- Misconfiguration and exposure templates for the configured target.
- Header, CSP, CORS, TLS, and SSL-related templates.
- Low-rate findings suitable for manual triage.

## What this phase does not test

- It does not crawl or discover additional targets by default.
- It does not update Nuclei templates automatically.
- It does not run fuzzing, brute-force, DoS, race, or intrusive templates by default.
- It does not authenticate to the application.
- It does not confirm findings automatically.

## Default command

```bash
./phases/05-nuclei.sh --workspace assessments/<company>/<target>/<run-id>
```

## Useful options

- `--yes`: run non-interactively after scope approval.
- `--clean`: delete prior Phase 5 evidence before rerunning.
- `--verbose`: print command and output monitoring details.
- `-h`, `--help`: print usage.

## Profile/depth controls

The default target is `TARGET_BASE_URL` only. Safe profile values keep rate and concurrency low, commonly `NUCLEI_RATE=1` and `NUCLEI_CONCURRENCY=1`.

Default tags are:

```text
exposure,misconfig,cors,csp,headers,tls,ssl
```

Default excluded tags are:

```text
fuzz,bruteforce,dos,race,intrusive
```

Deep and maintenance profiles may add limited technology or cloud/token detection tags, but still require explicit approval and manual review.

## Evidence produced

Evidence is written under:

```text
evidence/phase-5-nuclei/
status/phase-5-nuclei.status
```

Artifacts include target files, timestamped JSONL results, console logs, latest copies, `nuclei-summary.md`, and `nuclei-findings.json`. The phase supports Nuclei JSONL output modes compatible with `jsonl-export` or `jsonl` depending on installed Nuclei version.

## Expected results

A clean run may produce an empty or informational JSONL result set. Low-or-higher findings should be treated as triage leads for direct validation.

## How to interpret findings

Nuclei findings require manual validation. Confirm each material observation with direct requests, OpenSSL checks, or source evidence from earlier phases. Deduplicate Nuclei output against Phase 2 headers, Phase 1 TLS, and Phase 4 Nmap before reporting.

## Common false positives/noise

- Templates may match generic headers or framework fingerprints.
- CDN/WAF responses may trigger exposure or misconfiguration templates.
- Missing-header templates may duplicate Phase 2.
- Template behavior can vary by installed template version.

## Safety and performance notes

- Template updates are not automatic; the operator manages template currency separately.
- Low safe rate/concurrency reduces operational impact.
- Excluded tags are safety controls and should not be removed without explicit authorization.
- Do not expand targets beyond `TARGET_BASE_URL` unless scope and rate are approved.

## Troubleshooting

- Confirm Nuclei is installed or set `NUCLEI_BIN` in `config/tool-paths.env`.
- Review console logs for template path, JSONL mode, rate, and timeout errors.
- If JSONL parsing fails, verify the installed Nuclei version's output flag support.
- Rerun without `--clean` if preserving prior evidence; use `--clean` only for intentional reset.

## When to increase scope/depth

Increase tags, rate, or target list only with approval and an operational window. Prefer validating existing findings before broadening template scope.
