#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"
source "${REPO_ROOT}/lib/evidence.sh"
source "${REPO_ROOT}/lib/status.sh"

usage() {
  printf 'Usage: %s --workspace PATH [--yes] [--clean] [--verbose]\n' "$0"
}

YES="false"
CLEAN="false"
VERBOSE="${VERBOSE:-false}"
WORKSPACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      [[ $# -ge 2 ]] || die "--workspace requires a value"
      WORKSPACE="$2"
      shift 2
      ;;
    --yes)
      YES="true"
      shift
      ;;
    --clean)
      CLEAN="true"
      shift
      ;;
    --verbose)
      VERBOSE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${WORKSPACE}" ]] || die "--workspace is required"
WORKSPACE="$(absolute_path "${WORKSPACE}")"

PHASE_NAME="phase-4-nmap"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
NMAP_STATUS="failure"
NMAP_MESSAGE="Nmap phase did not complete."
NMAP_EXIT_CODE="1"
STATUS_READY="false"
SUMMARY_PATH=""
FINDINGS_PATH=""
OUT=""
CONSOLE_LOG=""
OUT_PREFIX=""

write_nmap_status_file() {
  local status="$1"
  local finished_utc="$2"
  local exit_code="$3"
  local message="$4"
  local status_file="${WORKSPACE}/status/${PHASE_NAME}.status"
  mkdir -p "${WORKSPACE}/status"
  cat > "${status_file}" <<EOF
STATUS=${status}
STARTED_UTC=${STARTED_UTC}
FINISHED_UTC=${finished_utc}
EXIT_CODE=${exit_code}
MESSAGE=$(shell_quote "${message}")
PHASE_RUN_ID=${PHASE_RUN_ID}
NMAP_PORTS=${NMAP_PORTS:-}
NMAP_MAX_RATE=${NMAP_MAX_RATE:-}
NMAP_SCAN_DELAY=${NMAP_SCAN_DELAY:-}
NMAP_MAX_RETRIES=${NMAP_MAX_RETRIES:-}
EOF
}

finish_status() {
  local exit_code="$1"
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${NMAP_STATUS}" == "failure" ]]; then
      NMAP_EXIT_CODE="${exit_code}"
    fi
    write_nmap_status_file "${NMAP_STATUS}" "${finished_utc}" "${NMAP_EXIT_CODE}" "${NMAP_MESSAGE}"
    write_status "${WORKSPACE}" "${PHASE_NAME}" "${NMAP_STATUS}" "${NMAP_MESSAGE}"
  fi
}
trap 'exit_code=$?; finish_status "${exit_code}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail_nmap() {
  NMAP_MESSAGE="$1"
  die "$1"
}

validate_nmap_ports() {
  local ports="$1"
  [[ -n "${ports}" ]] || fail_nmap "NMAP_PORTS must not be empty"
  [[ "${ports}" != *"-"* ]] || fail_nmap "NMAP_PORTS must not contain ranges for Phase 4: ${ports}"
  [[ "${ports}" != "0" && "${ports}" != "-" && "${ports}" != "all" ]] || fail_nmap "NMAP_PORTS must not request all ports: ${ports}"
  if [[ ! "${ports}" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    fail_nmap "NMAP_PORTS must be a comma-separated list of explicit TCP ports: ${ports}"
  fi
}

copy_latest() {
  local source_file="$1"
  local latest_file="$2"
  if [[ -f "${source_file}" ]]; then
    cp "${source_file}" "${latest_file}"
  fi
}

write_summary() {
  local summary_file="${SUMMARY_PATH}"
  "${PYTHON_BIN:-python3}" - "${OUT}" "${TARGET_HOST}" "${NMAP_PORTS}" "${NMAP_MAX_RATE}" "${NMAP_SCAN_DELAY}" "${NMAP_MAX_RETRIES}" "${PHASE_RUN_ID}" "${NMAP_STATUS}" "${NMAP_MESSAGE}" > "${summary_file}" <<'PY'
import json
import re
import sys
from collections import Counter
from pathlib import Path

out = Path(sys.argv[1])
host, ports, max_rate, scan_delay, max_retries, run_id, status, message = sys.argv[2:10]
raw = out / f"nmap-web-{run_id}.nmap"
xml = out / f"nmap-web-{run_id}.xml"
gnmap = out / f"nmap-web-{run_id}.gnmap"
console = out / f"nmap-web-console-{run_id}.txt"
findings_path = out / "nmap-findings.json"
try:
    findings = json.loads(findings_path.read_text(encoding="utf-8"))
except FileNotFoundError:
    findings = []
text = raw.read_text(encoding="utf-8", errors="replace") if raw.exists() else ""
open_ports = []
services = []
observations = []
for line in text.splitlines():
    m = re.match(r"^(\d+/tcp)\s+open\s+(\S+)(?:\s+(.*))?$", line)
    if m:
        open_ports.append(m.group(1))
        services.append(f"{m.group(1)} {m.group(2)} {(m.group(3) or '').strip()}".strip())
    if any(token in line.lower() for token in ["ssl-enum-ciphers", "least strength", "http-security-headers", "http-server-header", "http-title", "awselb"]):
        observations.append(line.strip())
severity = Counter(item.get("severity", "unknown") for item in findings if isinstance(item, dict))
statuses = Counter(item.get("status", "unknown") for item in findings if isinstance(item, dict))

print("# Nmap Web Service Validation Summary\n")
print("## Run\n")
print(f"- target host: {host}")
print(f"- ports scanned: {ports}")
print(f"- run ID: {run_id}")
print(f"- status: {status}")
print(f"- message: {message}\n")
print("## Profile Settings\n")
print(f"- NMAP_PORTS: {ports}")
print(f"- NMAP_MAX_RATE: {max_rate}")
print(f"- NMAP_SCAN_DELAY: {scan_delay}")
print(f"- NMAP_MAX_RETRIES: {max_retries}\n")
print("## Raw Output Files\n")
for path in [raw, xml, gnmap, console, out / "nmap-web-latest.nmap", out / "nmap-web-latest.xml", out / "nmap-web-latest.gnmap", out / "nmap-web-console-latest.txt"]:
    print(f"- {path.name}" if path.exists() else f"- {path.name} (not present)")
print("\n## Open Ports\n")
if open_ports:
    for port in open_ports:
        print(f"- {port}")
else:
    print("- none parsed")
print("\n## Detected Services\n")
if services:
    for service in services:
        print(f"- {service}")
else:
    print("- none parsed")
print("\n## TLS/Header Observations\n")
if observations:
    for observation in observations[:30]:
        print(f"- `{observation}`")
else:
    print("- none parsed")
print("\n## Findings Totals\n")
print("### By severity")
for key in ["medium", "low", "informational"]:
    print(f"- {key}: {severity.get(key, 0)}")
print("\n### By status")
for key in ["confirmed", "observed", "not_observed", "informational"]:
    print(f"- {key}: {statuses.get(key, 0)}")
print("\n## Limitations\n")
print("- This phase uses a deliberately constrained TCP web-port list and does not perform broad port scanning.")
print("- Nmap service and NSE script observations require manual review before being reported as vulnerabilities.")
print("- Missing security-header observations may duplicate Phase 2 and should be de-duplicated during reporting.")
print("- UDP, aggressive mode (-A), default/vuln/brute NSE categories, and all-port scans are intentionally not used.")
PY
}

print_phase_start() {
  printf '%s starting\n' "${PHASE_NAME}"
  printf 'workspace: %s\n' "${WORKSPACE}"
  printf 'evidence directory: %s\n' "${OUT}"
  printf 'target host: %s\n' "${TARGET_HOST}"
  printf 'ports: %s\n' "${NMAP_PORTS}"
  printf 'max rate: %s\n' "${NMAP_MAX_RATE}"
  printf 'scan delay: %s\n' "${NMAP_SCAN_DELAY}"
  printf 'max retries: %s\n' "${NMAP_MAX_RETRIES}"
  printf 'Nmap binary: %s\n' "${NMAP_BIN}"
  printf 'output prefix: %s\n' "${OUT_PREFIX}"
  printf 'monitor command: tail -f "%s"\n' "${CONSOLE_LOG}"
}

validate_workspace "${WORKSPACE}"
OUT="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_DIR="${WORKSPACE}/status"
mkdir -p "${OUT}" "${STATUS_DIR}"
STATUS_READY="true"

if [[ "${CLEAN}" == "true" ]]; then
  find "${OUT}" -maxdepth 1 -type f \( \
    -name 'nmap-web-[0-9]*T[0-9]*Z.nmap' -o \
    -name 'nmap-web-[0-9]*T[0-9]*Z.xml' -o \
    -name 'nmap-web-[0-9]*T[0-9]*Z.gnmap' -o \
    -name 'nmap-web-console-[0-9]*T[0-9]*Z.txt' -o \
    -name 'nmap-web-latest.nmap' -o \
    -name 'nmap-web-latest.xml' -o \
    -name 'nmap-web-latest.gnmap' -o \
    -name 'nmap-web-console-latest.txt' -o \
    -name 'nmap-summary.md' -o \
    -name 'nmap-findings.json' \
  \) -delete
fi

load_env_file "${WORKSPACE}/config/target.env"
require_env_vars TARGET_HOST PROFILE

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi
if [[ -f "${REPO_ROOT}/config/profiles/${PROFILE}.env" ]]; then
  load_env_file "${REPO_ROOT}/config/profiles/${PROFILE}.env"
fi

NMAP_PORTS="${NMAP_PORTS:-443}"
NMAP_MAX_RATE="${NMAP_MAX_RATE:-2}"
NMAP_SCAN_DELAY="${NMAP_SCAN_DELAY:-1s}"
NMAP_MAX_RETRIES="${NMAP_MAX_RETRIES:-2}"
validate_nmap_ports "${NMAP_PORTS}"

if [[ -n "${NMAP_BIN:-}" ]]; then
  [[ -x "${NMAP_BIN}" ]] || fail_nmap "configured NMAP_BIN is not executable: ${NMAP_BIN}"
else
  NMAP_BIN="$(first_existing_command nmap || true)"
fi
[[ -n "${NMAP_BIN}" ]] || fail_nmap "required tool missing: nmap (set NMAP_BIN in config/tool-paths.env or install nmap)"

while [[ -e "${OUT}/nmap-web-${PHASE_RUN_ID}.nmap" || -e "${OUT}/nmap-web-console-${PHASE_RUN_ID}.txt" ]]; do
  sleep 1
  PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
done

OUT_PREFIX="${OUT}/nmap-web-${PHASE_RUN_ID}"
CONSOLE_LOG="${OUT}/nmap-web-console-${PHASE_RUN_ID}.txt"
SUMMARY_PATH="${OUT}/nmap-summary.md"
FINDINGS_PATH="${OUT}/nmap-findings.json"

print_phase_start

nmap_cmd=(
  "${NMAP_BIN}"
  -Pn
  -p "${NMAP_PORTS}"
  --max-rate "${NMAP_MAX_RATE}"
  --scan-delay "${NMAP_SCAN_DELAY}"
  --max-retries "${NMAP_MAX_RETRIES}"
  -sV
  --script ssl-enum-ciphers,http-security-headers,http-title
  "${TARGET_HOST}"
  -oA "${OUT_PREFIX}"
)

if [[ "${VERBOSE}" == "true" ]]; then
  printf 'nmap command:'
  printf ' %q' "${nmap_cmd[@]}"
  printf '\n'
fi

set +e
"${nmap_cmd[@]}" >"${CONSOLE_LOG}" 2>&1
nmap_code=$?
set -e

copy_latest "${OUT_PREFIX}.nmap" "${OUT}/nmap-web-latest.nmap"
copy_latest "${OUT_PREFIX}.xml" "${OUT}/nmap-web-latest.xml"
copy_latest "${OUT_PREFIX}.gnmap" "${OUT}/nmap-web-latest.gnmap"
copy_latest "${CONSOLE_LOG}" "${OUT}/nmap-web-console-latest.txt"

"${PYTHON_BIN:-python3}" "${REPO_ROOT}/tools/parse-nmap.py" \
  --input "${OUT_PREFIX}.nmap" \
  --output "${FINDINGS_PATH}" \
  --target-host "${TARGET_HOST}" \
  --ports "${NMAP_PORTS}"

if [[ "${nmap_code}" -eq 0 ]]; then
  NMAP_STATUS="success"
  NMAP_MESSAGE="Nmap web service validation completed successfully."
else
  NMAP_STATUS="completed_with_warnings"
  NMAP_MESSAGE="Nmap exited with code ${nmap_code}; review console and raw output."
fi
NMAP_EXIT_CODE="${nmap_code}"
write_summary

printf '%s completed (%s)\n' "${PHASE_NAME}" "${NMAP_STATUS}"
printf 'status: %s\n' "${NMAP_STATUS}"
printf 'summary path: %s\n' "${SUMMARY_PATH}"
printf 'findings path: %s\n' "${FINDINGS_PATH}"
printf 'evidence directory: %s\n' "${OUT}"
