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

PHASE_NAME="phase-3-nikto"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
NIKTO_STATUS="failure"
NIKTO_MESSAGE="Nikto phase did not complete."
NIKTO_EXIT_CODE="1"
STATUS_READY="false"
ACTIVE_SCAN_PID=""
ACTIVE_HEARTBEAT_PID=""
ACTIVE_PID_FILE=""
TARGET_RESULTS=()
RAW_FILES=()
CONSOLE_FILES=()
HEARTBEAT_FILES=()
SCANNED_TARGETS=()
SUMMARY_PATH=""
FINDINGS_PATH=""

write_nikto_status_file() {
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
TARGET_MODE=${NIKTO_TARGET_MODE:-}
NIKTO_PAUSE=${NIKTO_PAUSE:-}
NIKTO_MAXTIME=${NIKTO_MAXTIME:-}
NIKTO_TUNING=${NIKTO_TUNING:-}
EOF
}

cleanup_active_scan() {
  if [[ -n "${ACTIVE_HEARTBEAT_PID}" ]]; then
    kill "${ACTIVE_HEARTBEAT_PID}" >/dev/null 2>&1 || true
    wait "${ACTIVE_HEARTBEAT_PID}" >/dev/null 2>&1 || true
    ACTIVE_HEARTBEAT_PID=""
  fi
  if [[ -n "${ACTIVE_PID_FILE}" && -f "${ACTIVE_PID_FILE}" ]]; then
    rm -f "${ACTIVE_PID_FILE}"
    ACTIVE_PID_FILE=""
  fi
}

finish_status() {
  local exit_code="$1"
  cleanup_active_scan
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${exit_code}" -eq 0 && "${NIKTO_STATUS}" == "failure" ]]; then
      NIKTO_STATUS="success"
    fi
    NIKTO_EXIT_CODE="${exit_code}"
    write_nikto_status_file "${NIKTO_STATUS}" "${finished_utc}" "${NIKTO_EXIT_CODE}" "${NIKTO_MESSAGE}"
    write_status "${WORKSPACE}" "${PHASE_NAME}" "${NIKTO_STATUS}" "${NIKTO_MESSAGE}"
  fi
}
trap 'exit_code=$?; finish_status "${exit_code}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail_nikto() {
  NIKTO_MESSAGE="$1"
  die "$1"
}

validate_workspace "${WORKSPACE}"
OUT="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_DIR="${WORKSPACE}/status"
mkdir -p "${OUT}" "${STATUS_DIR}"
STATUS_READY="true"

if [[ "${CLEAN}" == "true" ]]; then
  find "${OUT}" -maxdepth 1 -type f \( \
    -name 'nikto-*-[0-9]*T[0-9]*Z.txt' -o \
    -name 'nikto-*-console-[0-9]*T[0-9]*Z.txt' -o \
    -name 'nikto-*-heartbeat-[0-9]*T[0-9]*Z.txt' -o \
    -name 'nikto-*-latest.txt' -o \
    -name 'nikto-*-console-latest.txt' -o \
    -name 'nikto-*-heartbeat-latest.txt' -o \
    -name 'nikto-summary.md' -o \
    -name 'nikto-findings.json' \
  \) -delete
  find "${STATUS_DIR}" -maxdepth 1 -type f -name 'phase-3-nikto-*.pid' -delete
fi

load_env_file "${WORKSPACE}/config/target.env"
require_env_vars TARGET_BASE_URL LOGIN_URL TARGET_HOST PROFILE

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi
if [[ -f "${REPO_ROOT}/config/profiles/${PROFILE}.env" ]]; then
  load_env_file "${REPO_ROOT}/config/profiles/${PROFILE}.env"
fi

NIKTO_PAUSE="${NIKTO_PAUSE:-2}"
NIKTO_MAXTIME="${NIKTO_MAXTIME:-2h}"
NIKTO_TUNING="${NIKTO_TUNING:-x6}"
NIKTO_TARGET_MODE="${NIKTO_TARGET_MODE:-login}"
NIKTO_HEARTBEAT_INTERVAL="${NIKTO_HEARTBEAT_INTERVAL:-60}"

case "${NIKTO_TARGET_MODE}" in
  login|base|both) ;;
  *) fail_nikto "invalid NIKTO_TARGET_MODE: ${NIKTO_TARGET_MODE} (expected login, base, or both)" ;;
esac

if [[ -n "${NIKTO_BIN:-}" ]]; then
  [[ -x "${NIKTO_BIN}" ]] || fail_nikto "configured NIKTO_BIN is not executable: ${NIKTO_BIN}"
else
  NIKTO_BIN="$(first_existing_command nikto || true)"
fi
[[ -n "${NIKTO_BIN}" ]] || fail_nikto "required tool missing: nikto (set NIKTO_BIN in config/tool-paths.env or install nikto)"

copy_latest() {
  local source_file="$1"
  local latest_file="$2"
  if [[ -f "${source_file}" ]]; then
    cp "${source_file}" "${latest_file}"
  fi
}

check_pid_file() {
  local pid_file="$1"
  if [[ ! -f "${pid_file}" ]]; then
    return 0
  fi
  local existing_pid
  existing_pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if [[ "${existing_pid}" =~ ^[0-9]+$ ]] && kill -0 "${existing_pid}" >/dev/null 2>&1; then
    fail_nikto "Nikto scan already running for ${pid_file##*/} with PID ${existing_pid}"
  fi
  rm -f "${pid_file}"
}

human_size() {
  local file="$1"
  if [[ ! -e "${file}" ]]; then
    printf '0'
    return 0
  fi
  du -h "${file}" 2>/dev/null | awk '{print $1}'
}

line_count_if_available() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    printf '0'
    return 0
  fi
  wc -l < "${file}" 2>/dev/null | tr -d '[:space:]'
}

format_elapsed() {
  local elapsed="$1"
  printf '%02d:%02d:%02d' "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))"
}

emit_heartbeat_line() {
  local label="$1"
  local scan_pid="$2"
  local started_epoch="$3"
  local raw_file="$4"
  local console_file="$5"
  local heartbeat_file="$6"
  local now_epoch elapsed alive raw_size raw_lines console_size line
  now_epoch="$(date -u '+%s')"
  elapsed="$((now_epoch - started_epoch))"
  if kill -0 "${scan_pid}" >/dev/null 2>&1; then
    alive="running"
  else
    alive="stopped"
  fi
  raw_size="$(human_size "${raw_file}")"
  raw_lines="$(line_count_if_available "${raw_file}")"
  console_size="$(human_size "${console_file}")"
  line="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] ${label} ${alive} elapsed=$(format_elapsed "${elapsed}") raw_size=${raw_size} raw_lines=${raw_lines} console_size=${console_size}"
  printf '%s\n' "${line}" >> "${heartbeat_file}"
  if [[ "${VERBOSE}" == "true" ]]; then
    printf '%s\n' "${line}"
  fi
}

start_heartbeat() {
  local label="$1"
  local scan_pid="$2"
  local started_epoch="$3"
  local raw_file="$4"
  local console_file="$5"
  local heartbeat_file="$6"
  emit_heartbeat_line "${label}" "${scan_pid}" "${started_epoch}" "${raw_file}" "${console_file}" "${heartbeat_file}"
  (
    while kill -0 "${scan_pid}" >/dev/null 2>&1; do
      for _ in $(seq 1 "${NIKTO_HEARTBEAT_INTERVAL}"); do
        kill -0 "${scan_pid}" >/dev/null 2>&1 || exit 0
        sleep 1
      done
      kill -0 "${scan_pid}" >/dev/null 2>&1 || exit 0
      emit_heartbeat_line "${label}" "${scan_pid}" "${started_epoch}" "${raw_file}" "${console_file}" "${heartbeat_file}"
    done
  ) &
  ACTIVE_HEARTBEAT_PID="$!"
}

print_phase_start() {
  local status_file="${WORKSPACE}/status/${PHASE_NAME}.status"
  printf '%s starting\n' "${PHASE_NAME}"
  printf 'workspace: %s\n' "${WORKSPACE}"
  printf 'evidence directory: %s\n' "${OUT}"
  printf 'status file: %s\n' "${status_file}"
  printf 'target mode: %s\n' "${NIKTO_TARGET_MODE}"
  printf 'targets:\n'
  local target label url
  for target in "${TARGETS[@]}"; do
    label="${target%%=*}"
    url="${target#*=}"
    printf '  - %s: %s\n' "${label}" "${url}"
  done
  printf 'Nikto binary: %s\n' "${NIKTO_BIN}"
  printf 'NIKTO_PAUSE: %s\n' "${NIKTO_PAUSE}"
  printf 'NIKTO_MAXTIME: %s\n' "${NIKTO_MAXTIME}"
  printf 'NIKTO_TUNING: %s\n' "${NIKTO_TUNING}"
}

print_target_start() {
  local label="$1"
  local url="$2"
  local raw_out="$3"
  local console_out="$4"
  local heartbeat_out="$5"
  local pid_file="$6"
  printf 'Nikto target starting: %s\n' "${label}"
  printf 'target URL: %s\n' "${url}"
  printf 'raw output file: %s\n' "${raw_out}"
  printf 'console log file: %s\n' "${console_out}"
  printf 'heartbeat file: %s\n' "${heartbeat_out}"
  printf 'PID file: %s\n' "${pid_file}"
  printf 'monitor commands:\n'
  printf '  tail -f "%s"\n' "${console_out}"
  printf '  tail -f "%s"\n' "${heartbeat_out}"
  printf '  ./status.sh --workspace "%s"\n' "${WORKSPACE}"
}

run_nikto_target() {
  local label="$1"
  local url="$2"
  [[ -n "${url}" ]] || fail_nikto "missing URL for Nikto target mode ${NIKTO_TARGET_MODE}: ${label}"

  local raw_out="${OUT}/nikto-${label}-${PHASE_RUN_ID}.txt"
  local console_out="${OUT}/nikto-${label}-console-${PHASE_RUN_ID}.txt"
  local heartbeat_out="${OUT}/nikto-${label}-heartbeat-${PHASE_RUN_ID}.txt"
  local pid_file="${STATUS_DIR}/phase-3-nikto-${label}.pid"

  check_pid_file "${pid_file}"
  : > "${heartbeat_out}"
  print_target_start "${label}" "${url}" "${raw_out}" "${console_out}" "${heartbeat_out}" "${pid_file}"
  printf 'Starting Nikto target %s (%s) at %s\n' "${label}" "${url}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${console_out}"

  local started_epoch
  started_epoch="$(date -u '+%s')"
  set +e
  "${NIKTO_BIN}" -h "${url}" -ssl -Tuning "${NIKTO_TUNING}" -Pause "${NIKTO_PAUSE}" -maxtime "${NIKTO_MAXTIME}" -nointeractive -Format txt -output "${raw_out}" >> "${console_out}" 2>&1 &
  ACTIVE_SCAN_PID="$!"
  set -e
  printf '%s\n' "${ACTIVE_SCAN_PID}" > "${pid_file}"
  ACTIVE_PID_FILE="${pid_file}"
  start_heartbeat "${label}" "${ACTIVE_SCAN_PID}" "${started_epoch}" "${raw_out}" "${console_out}" "${heartbeat_out}"

  set +e
  wait "${ACTIVE_SCAN_PID}"
  local scan_code=$?
  set -e
  cleanup_active_scan
  ACTIVE_SCAN_PID=""

  printf 'Finished Nikto target %s with exit code %s at %s\n' "${label}" "${scan_code}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${console_out}"
  copy_latest "${raw_out}" "${OUT}/nikto-${label}-latest.txt"
  copy_latest "${console_out}" "${OUT}/nikto-${label}-console-latest.txt"
  copy_latest "${heartbeat_out}" "${OUT}/nikto-${label}-heartbeat-latest.txt"

  RAW_FILES+=("${raw_out}")
  CONSOLE_FILES+=("${console_out}")
  HEARTBEAT_FILES+=("${heartbeat_out}")
  SCANNED_TARGETS+=("${label}=${url}")
  TARGET_RESULTS+=("${label}:${scan_code}")

  if [[ "${scan_code}" -ne 0 ]]; then
    if [[ -s "${raw_out}" ]] && grep -Eiq 'maxtime|maximum execution time|time.*limit|timeout' "${console_out}" "${raw_out}" 2>/dev/null; then
      return 2
    fi
    if [[ -s "${raw_out}" ]]; then
      return 2
    fi
    return 1
  fi
  return 0
}

TARGETS=()
case "${NIKTO_TARGET_MODE}" in
  login)
    [[ -n "${LOGIN_URL}" ]] || fail_nikto "LOGIN_URL is required for NIKTO_TARGET_MODE=login"
    TARGETS+=("login=${LOGIN_URL}")
    ;;
  base)
    [[ -n "${TARGET_BASE_URL}" ]] || fail_nikto "TARGET_BASE_URL is required for NIKTO_TARGET_MODE=base"
    TARGETS+=("base=${TARGET_BASE_URL}")
    ;;
  both)
    [[ -n "${LOGIN_URL}" ]] || fail_nikto "LOGIN_URL is required for NIKTO_TARGET_MODE=both"
    [[ -n "${TARGET_BASE_URL}" ]] || fail_nikto "TARGET_BASE_URL is required for NIKTO_TARGET_MODE=both"
    TARGETS+=("login=${LOGIN_URL}" "base=${TARGET_BASE_URL}")
    ;;
esac

print_phase_start

NIKTO_STATUS="success"
NIKTO_MESSAGE="Nikto completed."
phase_exit=0
for target in "${TARGETS[@]}"; do
  label="${target%%=*}"
  url="${target#*=}"
  if run_nikto_target "${label}" "${url}"; then
    :
  else
    code=$?
    if [[ "${code}" -eq 2 ]]; then
      NIKTO_STATUS="completed_with_warnings"
      NIKTO_MESSAGE="Nikto completed with warnings; review per-target exit codes."
    else
      NIKTO_STATUS="completed_with_warnings"
      NIKTO_MESSAGE="Nikto target ${label} failed without raw output; continuing where safe."
      phase_exit=0
    fi
  fi
done

FINDINGS_PATH="${OUT}/nikto-findings.json"
SUMMARY_PATH="${OUT}/nikto-summary.md"
parser_args=("${REPO_ROOT}/tools/parse-nikto.py" --output "${FINDINGS_PATH}")
for raw_file in "${RAW_FILES[@]}"; do
  parser_args+=(--input "${raw_file}")
done
parser_args+=(--target "base=${TARGET_BASE_URL}" --target "login=${LOGIN_URL}")
"${PYTHON_BIN:-python3}" "${parser_args[@]}"

write_summary() {
  local summary_file="${SUMMARY_PATH}"
  "${PYTHON_BIN:-python3}" - "${OUT}" "${PHASE_RUN_ID}" "${STARTED_UTC}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${NIKTO_TARGET_MODE}" "${NIKTO_PAUSE}" "${NIKTO_MAXTIME}" "${NIKTO_TUNING}" "${NIKTO_STATUS}" "${NIKTO_MESSAGE}" "${TARGET_RESULTS[*]}" "${SCANNED_TARGETS[*]}" "${RAW_FILES[*]}" "${CONSOLE_FILES[*]}" > "${summary_file}" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

out = Path(sys.argv[1])
run_id, started, finished, mode, pause, maxtime, tuning, status, message = sys.argv[2:11]
results = sys.argv[11].split() if len(sys.argv) > 11 and sys.argv[11] else []
targets = sys.argv[12].split() if len(sys.argv) > 12 and sys.argv[12] else []
raw_files = sys.argv[13].split() if len(sys.argv) > 13 and sys.argv[13] else []
console_files = sys.argv[14].split() if len(sys.argv) > 14 and sys.argv[14] else []
findings_path = out / "nikto-findings.json"
try:
    findings = json.loads(findings_path.read_text(encoding="utf-8"))
except FileNotFoundError:
    findings = []
severity = Counter(item.get("severity", "unknown") for item in findings)
statuses = Counter(item.get("status", "unknown") for item in findings)
noise_titles = {"No CGI directories found", "Nikto update check failed", "Multiple IP addresses found for target"}
noise = [item for item in findings if item.get("title") in noise_titles]
notable = [item for item in findings if item.get("severity") in {"medium", "low"}]

print("# Nikto Summary\n")
print("## Run\n")
print(f"- run ID: {run_id}")
print(f"- started UTC: {started}")
print(f"- finished UTC: {finished}")
print(f"- status: {status}")
print(f"- message: {message}\n")
print("## Targets Scanned\n")
if targets:
    for target in targets:
        label, _, url = target.partition("=")
        result = next((r.partition(":")[2] for r in results if r.startswith(f"{label}:")), "unknown")
        print(f"- {label}: {url} (exit {result})")
else:
    print("- none")
print("\n## Profile Settings\n")
print(f"- target mode: {mode}")
print(f"- pause: {pause}")
print(f"- maxtime: {maxtime}")
print(f"- tuning: {tuning}\n")
print("## Evidence Files\n")
print("### Raw files")
for path in raw_files:
    print(f"- {Path(path).name}")
if not raw_files:
    print("- none")
print("\n### Console files")
for path in console_files:
    print(f"- {Path(path).name}")
if not console_files:
    print("- none")
print("\n## Findings Totals\n")
print("### By severity")
for key in ["medium", "low", "informational"]:
    print(f"- {key}: {severity.get(key, 0)}")
print("\n### By status")
for key in ["confirmed", "observed", "not_confirmed", "informational"]:
    print(f"- {key}: {statuses.get(key, 0)}")
print("\n## Notable Findings\n")
if notable:
    for item in notable[:10]:
        print(f"- {item.get('severity')}: {item.get('title')} — {item.get('url')}")
else:
    print("- No low-or-higher Nikto findings were parsed.")
print("\n## Ignored/Noise Observations\n")
if noise:
    for item in noise:
        print(f"- {item.get('title')}: {item.get('evidence')}")
else:
    print("- No common noise observations were parsed.")
print("\n## Limitations\n")
print("- Nikto findings are scanner observations and require manual validation before being reported as vulnerabilities.")
print("- This phase runs one target at a time with conservative tuning and does not perform CGI brute forcing with -C all.")
print("- Nonzero Nikto exit codes are preserved in the summary and status for reviewer context.")
PY
}
write_summary

if [[ "${NIKTO_STATUS}" == "success" ]]; then
  NIKTO_MESSAGE="Nikto completed successfully."
elif [[ "${NIKTO_STATUS}" == "completed_with_warnings" ]]; then
  :
fi

severity_counts() {
  "${PYTHON_BIN:-python3}" - "${FINDINGS_PATH}" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path
path = Path(sys.argv[1])
try:
    findings = json.loads(path.read_text(encoding="utf-8"))
except FileNotFoundError:
    findings = []
counts = Counter(item.get("severity", "unknown") for item in findings)
for severity in ["critical", "high", "medium", "low", "informational", "unknown"]:
    if counts.get(severity, 0) or severity in {"medium", "low", "informational"}:
        print(f"{severity}: {counts.get(severity, 0)}")
PY
}

printf 'phase-3-nikto completed (%s)\n' "${NIKTO_STATUS}"
printf 'final status: %s\n' "${NIKTO_STATUS}"
printf 'exit code: %s\n' "${phase_exit}"
printf 'summary path: %s\n' "${SUMMARY_PATH}"
printf 'findings path: %s\n' "${FINDINGS_PATH}"
printf 'evidence directory: %s\n' "${OUT}"
printf 'findings by severity:\n'
while IFS= read -r severity_line; do
  printf '  - %s\n' "${severity_line}"
done < <(severity_counts)
exit "${phase_exit}"
