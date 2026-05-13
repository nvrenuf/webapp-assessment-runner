# Webapp Assessment Runner

Reusable Kali Linux framework for repeatable, low-impact web application security assessments.

The repository contains reusable scripts, templates, profiles, parser stubs, and documentation. Engagement evidence is created outside the reusable framework code under generated workspaces:

```text
assessments/<company-slug>/<target-slug>/<run-id>/
```

No company name, domain, credentials, cookies, HAR files, logs, reports, or generated evidence should be committed to Git.

## Quick Start

```bash
./install.sh
./init-assessment.sh \
  --company "Example Company" \
  --engagement "External web baseline" \
  --target "https://app.example.test" \
  --profile safe \
  --auth none \
  --tester "Analyst Name" \
  --yes

./assess.sh --workspace assessments/example-company/app-example-test/<run-id>
./status.sh --workspace assessments/example-company/app-example-test/<run-id>
./report.sh --workspace assessments/example-company/app-example-test/<run-id>
```

Replace `<run-id>` with the run directory created by `init-assessment.sh`.

## Install

`install.sh` is the only script intended to run with elevated privileges. It checks for common Kali tools and prints package guidance. Assessment phases do not install packages and do not upgrade the system.

```bash
sudo ./install.sh
```

## Create Assessment

```bash
./init-assessment.sh \
  --company "Acme Inc" \
  --company-slug acme-inc \
  --engagement "Q2 unauthenticated baseline" \
  --target "https://www.example.com" \
  --login-path "/login" \
  --environment production \
  --profile safe \
  --auth none \
  --tester "Jane Analyst" \
  --output-root assessments \
  --yes
```

This creates the canonical workspace structure, renders target and scope config from templates, writes metadata, and creates phase evidence directories.

Use `--auth none` for unauthenticated testing and `--auth placeholder` to create an authenticated testing scaffold. The aliases `--auth no` and `--auth yes` are also accepted, along with other boolean-style aliases documented by `init-assessment.sh --help`.

For an authenticated testing scaffold:

```bash
./init-assessment.sh \
  --company "Acme Inc" \
  --engagement "Q2 authenticated scaffold" \
  --target "https://www.example.com" \
  --login-path "/login" \
  --environment staging \
  --profile safe \
  --auth placeholder \
  --tester "Jane Analyst" \
  --output-root assessments \
  --yes
```

## Run All Phases

```bash
./assess.sh --workspace assessments/acme-inc/www-example-com/20260513T172500Z
```

Current phase scripts are safe runnable stubs. They create evidence directories and status files only; they do not scan targets yet.

## Run One Phase

```bash
./phases/02-headers.sh --workspace assessments/acme-inc/www-example-com/20260513T172500Z
```

## Check Status

```bash
./status.sh --workspace assessments/acme-inc/www-example-com/20260513T172500Z
```

Status files are written under `status/` inside the selected workspace.

## Generate Report

```bash
./report.sh --workspace assessments/acme-inc/www-example-com/20260513T172500Z
```

Reports are written under the workspace `reports/` directory. Findings are normalized from tool parser output before being included in report-ready artifacts.

## Safety Model

- Defaults avoid brute force, denial of service, race testing, fuzzing, and intrusive behavior.
- Broad port scanning is not enabled by default.
- Evidence, logs, status files, and reports are always written under the selected workspace.
- Secrets are not printed and credentials are not stored in logs.
- Scanner output is evidence for review, not automatic confirmation of a vulnerability.
- Profiles are defined as `safe`, `balanced`, `deep`, and `maintenance`; phase stubs currently enforce no active scanning.

## Authenticated Testing Roadmap

Authenticated testing is intentionally a placeholder. Future work should add:

- Explicit authorization and scope confirmation.
- Secret handling that avoids console output and logs.
- Session capture procedures that exclude credentials from Git.
- Browser-driven passive crawling with rate limits.
- Clear separation between authenticated and unauthenticated evidence.

See [docs/authenticated-testing-plan.md](docs/authenticated-testing-plan.md).
