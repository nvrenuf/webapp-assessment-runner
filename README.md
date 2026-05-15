# Webapp Assessment Runner

Reusable Kali Linux framework for repeatable, low-impact web application security assessments.

The repository contains reusable scripts, templates, profiles, parser stubs, and documentation. Engagement evidence is created outside the reusable framework code under generated workspaces:

```text
assessments/<company-slug>/<target-slug>/<run-id>/
```

No company name, domain, credentials, cookies, HAR files, logs, reports, or generated evidence should be committed to Git.


## Operator Documentation

- [Operator guide](docs/operator-guide.md) for end-to-end workflow, safe defaults, common phase options, and production run behavior.
- [Profiles guide](docs/profiles.md) for `safe`, `balanced`, `deep`, and `maintenance` profile intent and override guidance.
- [Evidence and retention guide](docs/evidence-and-retention.md) for workspace evidence layout, timestamped outputs, Git hygiene, archiving, and retention.
- Phase documentation:
  - [Phase 0: Preflight](docs/phases/phase-0-preflight.md)
  - [Phase 1: TLS](docs/phases/phase-1-tls.md)
  - [Phase 2: Headers, CSP, and CORS](docs/phases/phase-2-headers-csp-cors.md)
  - [Phase 3: Nikto](docs/phases/phase-3-nikto.md)
  - [Phase 4: Nmap](docs/phases/phase-4-nmap.md)
  - [Phase 5: Nuclei](docs/phases/phase-5-nuclei.md)
  - [Phase 6: ZAP Passive](docs/phases/phase-6-zap-passive.md)
  - [Phase 7: Final Validation](docs/phases/phase-7-validation.md)
  - [Phase 8: Authenticated Testing](docs/phases/phase-8-authenticated.md)
  - [Phase 9: Reporting](docs/phases/phase-9-reporting.md)

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

`install.sh` checks Kali/Debian dependencies and can optionally install missing apt packages. It never runs `apt update`, `apt upgrade`, or `apt full-upgrade`. Assessment phases do not install packages and do not upgrade the system.

```bash
./install.sh --check-only
sudo ./install.sh --install-deps
```

Required tools are `bash`, `curl`, `openssl`, `nmap`, `nikto`, `nuclei`, `jq`, and `python3`. Flexible tools are `testssl` or `testssl.sh`, and `zaproxy`, `/usr/share/zaproxy/zap.sh`, or `owasp-zap`.

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

Current implemented phases use low-impact defaults and write evidence plus status files under the selected workspace. Preflight runs first and performs local Kali health checks plus one minimal reachability request after scope confirmation. Use `--skip-preflight` only when you intentionally want to bypass those checks.

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
