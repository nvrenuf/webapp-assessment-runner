# Phase 9: Reporting

## Purpose

Phase 9 turns existing workspace evidence into final deliverables. It collects phase outputs, preserves source findings, prioritizes Phase 7 direct validation, deduplicates scanner overlap, builds an evidence index, and can create a sanitized evidence archive.

Phase 9 is an offline reporting phase. It does **not** scan the target, authenticate, install dependencies, call external APIs, or modify prior phase evidence.

## Default commands

Generate reports through the top-level reporting entry point:

```bash
./report.sh --workspace assessments/<company>/<target>/<run-id>
```

Run the dedicated phase directly and create an evidence package:

```bash
./phases/09-reporting.sh --workspace assessments/<company>/<target>/<run-id> --yes --archive
```

## Options

- `--workspace <path>`: required workspace path.
- `--yes`: confirms non-interactive report generation.
- `--clean`: removes only Phase 9 outputs before regenerating them.
- `--verbose`: prints detailed generation metadata.
- `--archive`: creates a sanitized `reports/evidence-package-<run-id>.tar.gz` bundle.

## Inputs

Phase 9 loads workspace configuration from:

- `config/target.env`
- `config/metadata.json` when present
- `config/tool-paths.env` when present

If present, it reads finding files from:

- `evidence/phase-1-tls/tls-findings.json`
- `evidence/phase-2-headers/headers-findings.json`
- `evidence/phase-3-nikto/nikto-findings.json`
- `evidence/phase-4-nmap/nmap-findings.json`
- `evidence/phase-5-nuclei/nuclei-findings.json`
- `evidence/phase-6-zap/zap-findings.json`
- `evidence/phase-7-validation/validation-findings.json`
- `evidence/phase-8-authenticated/authenticated-findings.json`

Missing source finding files are recorded in `report-summary.md` rather than treated as fatal.

## Final Report Outputs

`./report.sh --workspace <workspace>` generates final report artifacts. The primary human-readable final report is `reports/technical-report.md`. The executive version is `reports/executive-summary.md`. The backward-compatible single report is `reports/report.md`. Structured final findings are `reports/findings-final.json` and `reports/findings-final.csv`. Create the evidence package with `./report.sh --workspace <workspace> --archive` or `./phases/09-reporting.sh --workspace <workspace> --yes --archive`.

Phase 9 reads optional workspace intake metadata from `config/client-intake.yaml` when present, records it in `reports/report-metadata.json`, and notes whether the intake appears placeholder-only in `reports/report-summary.md`. Missing or placeholder-only intake does not fail report generation.

## Outputs

Phase 9 writes report deliverables under `reports/`:

- `executive-summary.md`
- `technical-report.md`
- `findings-final.json`
- `findings-final.csv`
- `evidence-index.md`
- `evidence-index.json`
- `report-metadata.json`
- `report-summary.md`
- `report.md` as a backward-compatible copy of the technical report

It also writes Phase 9 evidence under `evidence/phase-9-reporting/`:

- `reporting-console-<PHASE_RUN_ID>.txt`
- `reporting-console-latest.txt`
- `normalization-notes-<PHASE_RUN_ID>.md`
- `normalization-notes-latest.md`
- `source-findings-<PHASE_RUN_ID>.json`
- `source-findings-latest.json`

The status file `status/phase-9-reporting.status` includes status, timestamps, exit code, message, `PHASE_RUN_ID`, report directory, and whether an archive was created.

## Normalization behavior

Phase 9 uses these rules:

1. Prefer Phase 7 direct validation findings over scanner findings.
2. Final findings normally include only `confirmed` findings, plus useful `observed`/`informational` items when they are appropriate report observations.
3. Scanner-only duplicates are not promoted when Phase 7 has a grouped finding.
4. `not_confirmed`, `not_observed`, `not_enabled`, `needs_review`, and `unvalidated` items remain in source findings, normalization notes, limitations, or informational observations.
5. Scanner findings from phases 2 through 6 are retained in `source-findings-latest.json` for traceability.
6. Final findings preserve source phases, source IDs, related source titles, and evidence file references.
7. Common rollups include:
   - CSP observations into `Permissive Content-Security-Policy`.
   - Missing browser hardening headers into `Missing recommended browser security headers`.
   - HSTS max-age below one year as its own finding.
8. CORS non-reflection, unconfirmed NULL/anonymous cipher support, modern TLS support, redirect context, login cache non-observations, and authenticated testing `not_enabled` are not final vulnerabilities.
9. Severity is not upgraded above Phase 7 validation evidence.
10. High or critical severity is not reported unless directly validated.

## Evidence index

`evidence-index.json` and `evidence-index.md` list files under workspace `evidence/`, `status/`, and `reports/`. Entries include:

- relative path
- file size
- modified UTC timestamp
- SHA-256 hash
- inferred phase
- inferred file type/category

The index is intended to make report claims traceable to local evidence while keeping all generated artifacts inside the selected workspace.

## Archive behavior

With `--archive`, Phase 9 creates:

```text
reports/evidence-package-<PHASE_RUN_ID>.tar.gz
reports/archive-manifest-<PHASE_RUN_ID>.json
reports/archive-manifest-latest.json
```

The package includes:

- `config/metadata.json`
- `config/scope.yaml`
- `status/`
- `evidence/`
- `reports/`

Obvious secret-like files are excluded, including:

- `config/auth.env`
- paths matching `*cookie*`
- paths matching `*session*`
- paths matching `*token*`
- paths matching `*.har`
- common browser profile directories

The archive manifest records included files, excluded files, hashes, and the exclusion rules.

## Clean behavior

`--clean` deletes only Phase 9 generated reports, Phase 9 evidence files, archive files/manifests, and `status/phase-9-reporting.status`. It does not delete prior phase evidence or source findings.

## Limitations

- Phase 9 does not create new evidence and cannot confirm a scanner finding by itself.
- If Phase 7 validation did not run, scanner findings are retained as source findings but not promoted to final vulnerabilities.
- Authenticated testing remains a limitation when credentials or approved test accounts are not available.
- Operators should review final wording and evidence before client delivery.
