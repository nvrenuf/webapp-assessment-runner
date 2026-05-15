# Start Here: Operator Runbook

This runbook is the shortest safe path for a low-impact unauthenticated web application assessment. It assumes the operator has basic Linux/Kali command-line familiarity, but not prior experience with this repository.

## 0. Before touching the target

Confirm these items before running any assessment command:

- Written authorization exists for the target, timing, and testing type.
- The target URL is in scope.
- The selected profile is approved. Use `safe` unless explicitly told otherwise.
- Authenticated testing is not assumed. It requires separate test accounts and approval.
- No credentials, cookies, bearer tokens, HAR files, customer data, or generated evidence will be committed to Git.

When in doubt, stop and clarify scope. Guessing is how assessments become incident reports.

## 1. Clone the repo and check dependencies

```bash
git clone https://github.com/nvrenuf/webapp-assessment-runner.git
cd webapp-assessment-runner
./install.sh --check-only
```

If dependencies are missing and you are approved to install packages on the assessment machine:

```bash
sudo ./install.sh --install-deps
```

Assessment phases do not install packages or upgrade the system.

## 2. Create a workspace

Use `example.com` only for a framework dry run. Use the real client target only when it is explicitly authorized.

### Dry-run example

```bash
WORKSPACE="$(./init-assessment.sh \
  --company "Example Company" \
  --company-slug example-company \
  --engagement "Example unauthenticated baseline" \
  --target "https://example.com" \
  --login-path "/" \
  --environment "test" \
  --profile safe \
  --auth none \
  --tester "Tester Name" \
  --output-root assessments \
  --yes | tail -n 1)"

echo "$WORKSPACE"
```

### Real authorized target example

Replace the values before running:

```bash
WORKSPACE="$(./init-assessment.sh \
  --company "Example Company" \
  --company-slug example-company \
  --engagement "External web baseline" \
  --target "https://app.example.com" \
  --login-path "/login" \
  --environment "staging" \
  --profile safe \
  --auth none \
  --tester "Tester Name" \
  --output-root assessments \
  --yes | tail -n 1)"

echo "$WORKSPACE"
```

The workspace is where all configs, evidence, status files, and reports are written.

## 3. Fill out client intake

Edit the workspace-local intake file before final reporting:

```bash
nano "$WORKSPACE/config/client-intake.yaml"
```

Keep it non-secret. Do not put passwords, tokens, cookies, API keys, HAR files, session values, private keys, or customer data in this file.

The assessment can run if intake is still placeholder-only, but the final report will be less useful.

## 4. Run the unauthenticated baseline

Preferred normal path:

```bash
./assess.sh --workspace "$WORKSPACE"
```

`assess.sh` runs preflight and the unauthenticated baseline phases through final validation. It does not run Phase 8 authenticated testing and it does not generate the final report.

Use status while long-running phases execute:

```bash
./status.sh --workspace "$WORKSPACE"
```

## 5. If a phase fails or takes too long

Start with the status files:

```bash
find "$WORKSPACE/status" -maxdepth 1 -type f -print -exec cat {} \;
```

Review the phase evidence directory:

```bash
find "$WORKSPACE/evidence" -maxdepth 2 -type f | sort
```

It is acceptable to rerun an individual phase. Use `--clean` only when you intentionally want to replace that phase's evidence:

```bash
./phases/02-headers.sh --workspace "$WORKSPACE" --yes --verbose
```

For development or a failed test run only:

```bash
./phases/02-headers.sh --workspace "$WORKSPACE" --yes --clean --verbose
```

## 6. Run Phase 8 only when authentication is in scope

Phase 8 is currently a safe scaffold. It does not authenticate or test authorization by itself.

Run it only when authenticated testing is part of the engagement plan:

```bash
./phases/08-authenticated.sh --workspace "$WORKSPACE" --yes --verbose
```

If no credentials or test accounts are available, `AUTH_READINESS=not_enabled` is expected for unauthenticated workspaces.

## 7. Generate the final report

Yes, you need to run `report.sh` after `assess.sh`.

`assess.sh` collects and validates evidence. `report.sh` generates final report artifacts from that evidence.

```bash
./report.sh --workspace "$WORKSPACE" --yes --archive --verbose
```

Primary outputs:

```text
$WORKSPACE/reports/technical-report.md
$WORKSPACE/reports/executive-summary.md
$WORKSPACE/reports/report.md
$WORKSPACE/reports/findings-final.json
$WORKSPACE/reports/findings-final.csv
$WORKSPACE/reports/evidence-index.md
$WORKSPACE/reports/evidence-package-<run-id>.tar.gz
```

## 8. Review before delivery

Inspect the report summary and final findings:

```bash
cat "$WORKSPACE/reports/report-summary.md"
cat "$WORKSPACE/reports/findings-final.json" | jq .
```

Check the archive does not include obvious secret-like files:

```bash
tar -tzf "$WORKSPACE"/reports/evidence-package-*.tar.gz \
  | grep -Ei 'auth.env|cookie|session|token|\.har|browser-profile|chrome-profile|firefox-profile' || true
```

Expected output from the archive check is no matching secret-like paths.

## 9. What not to commit

Never commit generated workspace content or sensitive files:

```text
assessments/**
evidence/**
reports/**
logs/**
*.tar.gz
*.har
*cookie*
*session*
*token*
secrets/
.env
```

## 10. Where to read more

- `README.md` for repository overview and quick start.
- `docs/operator-guide.md` for the full workflow.
- `docs/client-intake.md` for intake guidance.
- `docs/profiles.md` for profile behavior.
- `docs/evidence-and-retention.md` for evidence handling.
- `docs/phases/` for phase-specific details.
