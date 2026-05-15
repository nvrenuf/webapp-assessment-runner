# Client Intake

Client intake captures the authorization, scope, contacts, application context, and reporting expectations that make a final assessment report understandable to reviewers. It keeps planning context close to the workspace so Phase 9 can include useful metadata without adding client-specific material to the reusable repository.

## When to fill it out

`./init-assessment.sh` copies `templates/client-intake.yaml.example` to:

```text
<workspace>/config/client-intake.yaml
```

Operators should edit that workspace-local file after the engagement is authorized and before final reporting. The phases do not require the file to be completed, and assessment execution should not be blocked if the file is still placeholder-only.

## What to store

Use the intake file for non-secret engagement context, such as:

- client and engagement names
- approved scope and target URLs
- testing windows and traffic constraints
- authorization references and approved testing types
- business, technical, security, and report contacts
- application roles, workflows, integrations, and reporting requirements

Repository examples must use `example.com` and `Example Company` placeholders only.

## What not to store

Do not store credentials, passwords, API keys, session cookies, bearer tokens, HAR files, browser profiles, private keys, exploit payloads, or real sensitive data in `client-intake.yaml`. Use approved secret-handling processes outside this repository for any credential exchange. Completed intake files are generated inside `assessments/<company-slug>/<target-slug>/<run-id>/` workspaces and must not be committed.

## How Phase 9 uses intake

Phase 9 reads `<workspace>/config/client-intake.yaml` when it exists. The report generator uses a standard-library-only parser for the shallow template structure and merges parsed values into `reports/report-metadata.json` under `client_intake`. Useful fields, such as engagement contacts, scope, authorization, authenticated testing readiness, and reporting preferences, are summarized in `reports/executive-summary.md` and `reports/technical-report.md`.

If the intake file is missing, Phase 9 still generates reports and records that intake was not found. If the file appears placeholder-only, Phase 9 still completes and adds a note in `reports/report-summary.md` so operators know to review or complete intake before client delivery.
