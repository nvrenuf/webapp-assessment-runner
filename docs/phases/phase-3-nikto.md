# Phase 3: Nikto

## Purpose

Phase 3 runs a low-impact Nikto web server scan to identify common server misconfigurations and outdated exposure signals for manual review.

## What this phase tests

- Common web server misconfiguration signatures.
- Known default files or risky paths within the configured target mode.
- Basic server behavior visible to Nikto with conservative tuning.
- Profile-controlled pacing, target selection, and maximum run time.

## What this phase does not test

- It does not run `-C all` CGI enumeration.
- It does not run parallel Nikto scans by default.
- It does not perform HTML and TXT double runs for the same target.
- It does not authenticate or crawl complex workflows.
- It does not confirm vulnerabilities automatically.

## Default command

```bash
./phases/03-nikto.sh --workspace assessments/<company>/<target>/<run-id>
```

For monitoring:

```bash
./phases/03-nikto.sh --workspace assessments/<company>/<target>/<run-id> --yes --verbose
```

## Useful options

- `--yes`: run non-interactively after scope approval.
- `--clean`: delete prior Nikto evidence for Phase 3 before rerunning. This removes prior raw output, console logs, heartbeat logs, summaries, and parsed findings.
- `--verbose`: print monitoring details and heartbeat information.
- `-h`, `--help`: print usage.

## Profile/depth controls

Nikto profile defaults are:

| Profile | Pause | Max time | Target mode |
| --- | ---: | --- | --- |
| `safe` | `5` | `2h` | `login` |
| `balanced` | `2` | `2h` | `login` |
| `deep` | `1` | `4h` | `both` |

`login` targets the configured login URL. `base` targets the base URL. `both` targets both when explicitly selected by profile or override.

## Evidence produced

Evidence is written under:

```text
evidence/phase-3-nikto/
status/phase-3-nikto.status
```

Artifacts include timestamped Nikto raw output, console logs, heartbeat logs, `latest` convenience copies, `nikto-summary.md`, and `nikto-findings.json`.

## Expected results

A quiet result may show no low-or-higher parsed findings. Informational server details may still appear and should be reviewed for context.

## How to interpret findings

Nikto output is scanner evidence requiring manual validation. Confirm paths, headers, and server behavior directly before reporting. Treat parsed findings as a triage list for Phase 7 validation, not as final vulnerabilities.

## Common false positives/noise

- Nikto update check returning `403`.
- Server banner changed warnings.
- Wildcard certificate observations.
- No CGI directories found.
- Generic server header disclosures that are informational only.

## Safety and performance notes

- The phase is paced by profile values and avoids high-volume options.
- `--verbose` helps monitor long runs with heartbeat output.
- `--clean` deletes prior Nikto evidence and should not be used for production evidence unless intentional.
- No `-C all`, no default parallel scans, and no duplicate HTML+TXT scans are used by default.

## Troubleshooting

- Confirm Nikto is installed or set `NIKTO_BIN` in `config/tool-paths.env`.
- Review the console log and heartbeat file if the phase appears stalled.
- Check for a stale PID file in `status/` if a previous run was interrupted.
- Lower depth or return to `safe` if the target owner reports operational concerns.

## When to increase scope/depth

Move from `safe` to `balanced` or `deep` only when authorized, when prior phases are stable, and when the operator needs broader coverage of both base and login URLs. Use maintenance windows for longer deep runs.
