# Agent Instructions

## Coding Standards

- Shell scripts use `#!/usr/bin/env bash`, `set -Eeuo pipefail`, safe quoting, and clear error messages.
- Keep reusable code in `lib/`, `tools/`, `phases/`, `config/`, `templates/`, and `docs/`.
- Keep generated engagement data only inside workspaces under `assessments/<company-slug>/<target-slug>/<run-id>/`.
- Do not hardcode company names, domains, secrets, cookies, sessions, or engagement-specific details.
- Prefer small, readable shell functions over duplicated inline logic.
- Python tools must be CLI-runnable and syntactically valid.

## Test Commands

```bash
make test
make shell-syntax
make python-check
bash -n install.sh init-assessment.sh assess.sh status.sh report.sh phases/*.sh lib/*.sh
python3 -m py_compile tools/*.py
pytest
```

## Safety Boundaries

- Do not add brute force, denial of service, race, fuzzing, credential stuffing, or intrusive behavior to defaults.
- Do not run broad port scanning by default.
- Do not install packages, upgrade Kali, or require root during assessment phases.
- Assessment scripts must not generate evidence outside the selected workspace.
- Authenticated testing remains placeholder-only until explicit safe handling exists.

## Git Hygiene

- Never commit credentials, cookies, HAR files, session files, generated evidence, logs, reports, or workspaces.
- `.gitignore` must continue excluding generated assessment data and secret material.
- Scanner findings are not automatically confirmed vulnerabilities. Treat them as unvalidated findings until manually reviewed.
