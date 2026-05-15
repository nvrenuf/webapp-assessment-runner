# Operator Guide

This guide describes the recommended operator workflow for running the webapp assessment runner safely and repeatably. It is written for analysts who need to create a workspace, run individual phases, preserve evidence, and decide when to increase scope or depth.

## Safety model

The runner is designed around low-impact defaults:

- Work is performed inside an explicit workspace under `assessments/<company-slug>/<target-slug>/<run-id>/`.
- Evidence, logs, status files, and reports are written inside that workspace.
- Default profiles avoid brute force, denial of service, race testing, fuzzing, credential stuffing, broad port scanning, UDP scans, and intrusive active scanning.
- Scanner findings are observations, not automatically confirmed vulnerabilities.
- Phase 7 validation and Phase 9 report normalization decide which items become confirmed report findings.
- Authenticated testing requires dedicated test accounts, explicit authorization, and careful secret handling.

## End-to-end workflow

### 1. Clone the repository

```bash
git clone <repo-url> webapp-assessment-runner
cd webapp-assessment-runner
```

### 2. Install or check dependencies

Use check-only mode when you want to verify the local Kali/Debian environment without installing anything:

```bash
./install.sh --check-only
```

If the operator has approval to install missing packages on the assessment machine, install dependencies explicitly:

```bash
sudo ./install.sh --install-deps
```

Assessment phases themselves do not install packages, run system upgrades, or require root as part of target testing.

### 3. Create a workspace

Create a new workspace for each official run. This keeps evidence complete, timestamped, and easy to retain or archive.

```bash
./init-assessment.sh \
  --company "Example Company" \
  --engagement "External web baseline" \
  --target "https://app.example.test" \
  --login-path "/login" \
  --environment production \
  --profile safe \
  --auth none \
  --tester "Analyst Name" \
  --output-root assessments \
  --yes
```

Record the generated workspace path, for example:

```text
assessments/example-company/app-example-test/20260515T120000Z
```

Use `--auth placeholder` only when you want the Phase 8 authenticated-testing scaffold. Phase 8 remains scaffold-only until real credential handling and explicit authenticated automation are implemented; do not place real credentials in Git, command history, workspace `auth.env`, or reusable repository files.

### 4. Run preflight

Preflight validates the workspace, local tool availability, DNS, and one low-impact reachability request.

```bash
./phases/00-preflight.sh --workspace assessments/example-company/app-example-test/20260515T120000Z --yes
```

Do not skip preflight for production runs unless you already completed the same checks and documented why they are not needed.

### 5. Run phases individually

Running phases individually gives the operator control over timing, monitoring, and evidence review:

```bash
./phases/01-tls.sh --workspace assessments/example-company/app-example-test/20260515T120000Z --yes
./phases/02-headers.sh --workspace assessments/example-company/app-example-test/20260515T120000Z --yes
./phases/03-nikto.sh --workspace assessments/example-company/app-example-test/20260515T120000Z --yes --verbose
./phases/04-nmap.sh --workspace assessments/example-company/app-example-test/20260515T120000Z --yes --verbose
./phases/05-nuclei.sh --workspace assessments/example-company/app-example-test/20260515T120000Z --yes --verbose
./phases/08-authenticated.sh --workspace assessments/example-company/app-example-test/20260515T120000Z --yes
```

`assess.sh` can run the current phase sequence, but individual phase execution is preferred when the operator needs approval gates, manual review between phases, or close monitoring of long-running tools.

### 6. Monitor long-running phases

Use `--verbose` for phases that support live progress output or heartbeat logging, especially Nikto, Nmap, and Nuclei. Verbose mode helps answer: is the tool still running, which evidence file is growing, and what command should be tailed?

Useful monitoring commands include:

```bash
./status.sh --workspace assessments/example-company/app-example-test/20260515T120000Z
find assessments/example-company/app-example-test/20260515T120000Z/status -type f -maxdepth 1 -print
find assessments/example-company/app-example-test/20260515T120000Z/evidence -type f -maxdepth 3 -print
```

For Nikto and Nuclei, phase output prints the console or heartbeat file that can be tailed.

### 7. Validate and normalize findings

Scanner results are not final findings. Review evidence, then use direct validation checks in Phase 7 to confirm, contradict, or downgrade observations. Report normalization in Phase 9 should deduplicate related observations and roll granular scanner output into report-friendly findings.

Examples:

- Multiple CSP observations can roll up into one `Permissive Content Security Policy` finding.
- Missing browser headers can roll up into one `Missing Recommended Browser Security Headers` finding.
- Scanner observations that cannot be reproduced should remain informational or be omitted from the final report.

### 8. Generate reports

```bash
./report.sh --workspace assessments/example-company/app-example-test/20260515T120000Z
```

Reports are written under the workspace `reports/` directory. Keep reports and raw evidence out of Git.

## Common options

### `--yes`

Use `--yes` when the scope has already been reviewed and you want non-interactive execution, such as inside a controlled runbook. Do not use it to bypass authorization or scope confirmation. For production work, document the approved target and profile before using `--yes`.

### `--clean`

`--clean` deletes prior evidence for the selected phase before running it again. This is useful for development, test workspaces, or an intentional phase reset after a failed dry run.

Do not use `--clean` during production evidence collection unless the deletion is intentional and documented. Prefer creating a new workspace for official reruns so the original timestamped evidence remains intact.

### `--verbose`

Use `--verbose` for long-running or tool-driven phases when you want extra progress information, command details, heartbeat files, or tail instructions. Verbose output is not a substitute for reviewing the final evidence and status files.

## Recommended production behavior

- Create a new workspace for each official run.
- Avoid `--clean` when preserving evidence matters.
- Use `--clean` only for test/dev or intentional reset.
- Keep evidence, logs, reports, cookies, HAR files, credentials, and workspaces out of Git.
- Use the `safe` profile first unless the rules of engagement approve a deeper profile.
- Treat all scanner output as unvalidated until Phase 7 direct checks and Phase 9 reporting decisions are complete.
