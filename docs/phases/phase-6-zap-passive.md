# Phase 6: ZAP Passive Web Assessment

## Purpose

Phase 6 runs an unauthenticated, passive-only OWASP ZAP assessment against the configured login URL. It starts a local ZAP daemon, performs a deliberately limited traditional spider to generate traffic, waits for the passive scanner queue, exports ZAP alerts and an HTML report, then normalizes alerts into runner findings.

The implementation uses the ZAP API directly and does **not** rely on `zap-baseline.py`, which may be absent on Kali installations.

## Default command

```bash
./phases/06-zap-passive.sh --workspace assessments/<company>/<target>/<run-id>
```

Useful options:

- `--workspace <path>`: required workspace path.
- `--yes`: accepted for workflow consistency and future prompts.
- `--clean`: removes prior Phase 6 raw ZAP files, latest copies, `zap-summary.md`, `zap-findings.json`, and the Phase 6 PID file before continuing.
- `--verbose`: prints daemon startup polling, spider progress, and passive records remaining.

## Configuration loaded

The phase loads these files in order:

1. `<workspace>/config/target.env`
2. `<workspace>/config/tool-paths.env`, when present
3. `config/profiles/<PROFILE>.env`, when present

`LOGIN_URL` is the assessment target. `ZAP_BIN` may be set in `tool-paths.env`; otherwise the phase detects `/usr/share/zaproxy/zap.sh`, `zaproxy`, or `owasp-zap`.

Fallback ZAP defaults are safe profile values:

```text
ZAP_PORT=8090
ZAP_SPIDER_MAX_CHILDREN=5
ZAP_SPIDER_RECURSE=false
ZAP_PASSIVE_TIMEOUT=600
ZAP_START_TIMEOUT=120
ZAP_AJAX_SPIDER=false
ZAP_ACTIVE_SCAN=false
```

## Implemented workflow

1. Validates the workspace, target configuration, ZAP settings, PID file, and local ZAP port.
2. Starts ZAP with a local-only daemon binding:

   ```text
   -daemon -host 127.0.0.1 -port <ZAP_PORT> -config api.disablekey=true -config database.recoverylog=false
   ```

3. Polls `http://127.0.0.1:<ZAP_PORT>/JSON/core/view/version/` until ready or `ZAP_START_TIMEOUT` is reached.
4. Starts the traditional spider against `LOGIN_URL` with configured `recurse` and `maxChildren` limits.
5. Polls spider status until complete.
6. Polls `/JSON/pscan/view/recordsToScan/` until no records remain or `ZAP_PASSIVE_TIMEOUT` is reached.
7. Exports alerts JSON and the ZAP HTML report.
8. Parses alerts with `tools/parse-zap.py` into normalized findings.
9. Writes `zap-summary.md`, status metadata, latest copies, and shuts ZAP down cleanly.

If the passive scan wait times out but alerts can still be exported, the phase completes with warnings and documents the remaining passive queue state.

## Evidence produced

All Phase 6 evidence is kept under:

```text
<workspace>/evidence/phase-6-zap/
```

Timestamped raw artifacts:

- `zap-daemon-console-<run-id>.txt`
- `zap-version-<run-id>.json`
- `zap-spider-start-<run-id>.json`
- `zap-spider-status-<run-id>.json`
- `zap-passive-records-left-<run-id>.json`
- `zap-alerts-<run-id>.json`
- `zap-report-<run-id>.html`

Latest copies:

- `zap-daemon-console-latest.txt`
- `zap-version-latest.json`
- `zap-spider-start-latest.json`
- `zap-spider-status-latest.json`
- `zap-passive-records-left-latest.json`
- `zap-alerts-latest.json`
- `zap-report-latest.html`

Stable outputs:

- `zap-summary.md`
- `zap-findings.json`

Status files:

- `<workspace>/status/phase-6-zap.status`
- `<workspace>/status/phase-6-zap.json`
- transient `<workspace>/status/phase-6-zap.pid` while ZAP is running

## Safety limits

Phase 6 intentionally does not perform active or intrusive testing.

- No ZAP active scan is implemented or allowed. If `ZAP_ACTIVE_SCAN=true`, the phase fails clearly.
- No AJAX spider is run by default. If `ZAP_AJAX_SPIDER=true`, the phase fails because AJAX spidering is reserved for a later authenticated/deep implementation.
- No forced browsing, fuzzing, brute forcing, attacks, or authentication are performed.
- ZAP binds only to `127.0.0.1`.
- The API key is disabled only for this local daemon use.
- Evidence is written only inside the selected workspace.

## Finding interpretation

`tools/parse-zap.py` maps ZAP passive alerts into the runner finding schema. High and medium alerts are marked `needs_review`, low alerts are `observed`, and informational alerts are `informational`. Categories include CSP, headers, cookies, cache, XSS, CORS, and miscellaneous observations.

ZAP findings are scanner observations. Validate material issues in Phase 7 before reporting, and de-duplicate missing-header or CSP observations against earlier phases.

## Troubleshooting

- **ZAP not found**: install ZAP or set `ZAP_BIN` in `<workspace>/config/tool-paths.env`.
- **Port already in use**: stop the existing local ZAP process or override `ZAP_PORT`; the phase fails with “ZAP port already in use; stop existing ZAP or override ZAP_PORT.”
- **Stale PID**: stale PID files are removed automatically; live PID files fail clearly to avoid conflicting daemon ownership.
- **Startup timeout**: review `zap-daemon-console-latest.txt`, increase `ZAP_START_TIMEOUT`, or verify Java/ZAP can start in the environment.
- **Passive timeout**: review `zap-passive-records-left-latest.json`; partial alerts and the HTML report should still be exported when possible.
- **Unexpected alerts/noise**: treat all ZAP passive alerts as unvalidated until manually reviewed.
