# Evidence and Retention Guide

This guide explains how assessment evidence is organized, what should stay out of Git, and how to retain or archive workspaces safely.

## Workspace structure

Each assessment run creates a workspace under:

```text
assessments/<company-slug>/<target-slug>/<run-id>/
```

Typical workspace contents include:

```text
config/        Target, scope, tool-path, and optional auth placeholder config
 evidence/     Phase-specific raw outputs and summaries
 logs/         Runner or operator logs when present
 reports/      Normalized findings and generated reports
 status/       Per-phase status files and transient PID files
```

Phase evidence directories follow the phase name where possible, for example:

```text
evidence/phase-0-preflight/
evidence/phase-1-tls/
evidence/phase-2-headers/
evidence/phase-3-nikto/
evidence/phase-4-nmap/
evidence/phase-5-nuclei/
evidence/phase-6-zap/
evidence/phase-7-validation/
evidence/phase-8-authenticated/
```

## Timestamped raw outputs and latest copies

Phases that execute external tools generally write timestamped raw outputs, such as:

```text
nikto-login-20260515T120000Z.txt
nuclei-results-20260515T120000Z.jsonl
```

They may also write convenience copies such as:

```text
nikto-login-latest.txt
nuclei-results-latest.jsonl
```

Use timestamped files for production evidence references because they identify the exact run. Use `latest` files for quick review only. If a phase is rerun without `--clean`, older timestamped files should remain available for comparison.

## `--clean` and evidence deletion

`--clean` deletes prior evidence for the selected phase before creating new evidence. This is useful for test workspaces, development, or intentional reset after a failed trial run.

Do not use `--clean` for production evidence collection unless deleting prior phase evidence is intentional, approved, and documented. For official reruns, create a new workspace instead.

## What not to commit

Never commit:

- Workspaces under `assessments/`.
- Raw evidence, logs, reports, archives, or status files.
- Credentials, cookies, tokens, session files, HAR files, screenshots containing sensitive data, or `auth.env` files with real secrets.
- Company-specific target names, domains, or engagement details in reusable repository files.

The reusable repository should contain scripts, templates, profiles, and generic documentation only.

## Archive and encryption recommendations

For completed official runs:

1. Review that the workspace contains only authorized-scope evidence.
2. Generate final reports and an evidence index.
3. Create an archive of the whole workspace or of approved evidence/report subsets.
4. Encrypt the archive using the client-approved method, such as an organization-managed encrypted storage location or recipient-specific encryption.
5. Store keys, passwords, or recovery material outside the archive and outside Git.
6. Record the archive name, hash, retention period, and storage location in the engagement closeout notes.

## Retention considerations

Retention depends on contract, legal, and organizational requirements. Decide and document:

- How long raw evidence is retained.
- Whether final reports are retained longer than raw tool output.
- Who can access sensitive evidence.
- How deletion is verified at the end of the retention period.
- Whether authenticated-session artifacts require shorter retention.

If in doubt, retain less sensitive derived reporting and avoid retaining credentials, cookies, tokens, or full session captures unless explicitly required.
