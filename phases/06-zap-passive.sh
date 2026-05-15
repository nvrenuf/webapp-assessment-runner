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

PHASE_NAME="phase-6-zap"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
ZAP_STATUS="failure"
ZAP_MESSAGE="ZAP passive phase did not complete."
ZAP_EXIT_CODE="1"
STATUS_READY="false"
ZAP_PID=""
ZAP_STARTED="false"
PASSIVE_TIMED_OUT="false"
PID_FILE=""
CONSOLE_LOG=""

write_zap_status_file() {
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
ZAP_PORT=${ZAP_PORT:-}
ZAP_SPIDER_MAX_CHILDREN=${ZAP_SPIDER_MAX_CHILDREN:-}
ZAP_SPIDER_RECURSE=${ZAP_SPIDER_RECURSE:-}
ZAP_PASSIVE_TIMEOUT=${ZAP_PASSIVE_TIMEOUT:-}
ZAP_START_TIMEOUT=${ZAP_START_TIMEOUT:-}
ZAP_AJAX_SPIDER=${ZAP_AJAX_SPIDER:-}
ZAP_ACTIVE_SCAN=${ZAP_ACTIVE_SCAN:-}
EOF
}

zap_api_url() {
  local path="$1"
  printf 'http://127.0.0.1:%s%s' "${ZAP_PORT}" "${path}"
}

urlencode() {
  "${PYTHON_BIN:-python3}" -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

zap_get() {
  local path="$1"
  local output="$2"
  curl -fsS --connect-timeout 2 --max-time 30 "$(zap_api_url "${path}")" -o "${output}"
}

zap_get_stdout() {
  local path="$1"
  curl -fsS --connect-timeout 2 --max-time 30 "$(zap_api_url "${path}")"
}

cleanup_zap() {
  local exit_code="$1"
  if [[ "${ZAP_STARTED}" == "true" && -n "${ZAP_PID}" ]]; then
    if kill -0 "${ZAP_PID}" >/dev/null 2>&1; then
      printf 'Requesting ZAP daemon shutdown at %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${CONSOLE_LOG}"
      set +e
      curl -fsS --connect-timeout 2 --max-time 10 "$(zap_api_url '/JSON/core/action/shutdown/')" >> "${CONSOLE_LOG}" 2>&1
      local shutdown_code=$?
      set -e
      local waited=0
      while kill -0 "${ZAP_PID}" >/dev/null 2>&1 && [[ "${waited}" -lt 20 ]]; do
        sleep 1
        waited=$((waited + 1))
      done
      if kill -0 "${ZAP_PID}" >/dev/null 2>&1; then
        printf 'Clean ZAP shutdown did not complete (API exit %s); killing PID %s\n' "${shutdown_code}" "${ZAP_PID}" >> "${CONSOLE_LOG}"
        kill "${ZAP_PID}" >/dev/null 2>&1 || true
        sleep 2
        kill -9 "${ZAP_PID}" >/dev/null 2>&1 || true
      fi
    fi
  fi
  if [[ -n "${PID_FILE}" ]]; then
    rm -f "${PID_FILE}"
  fi
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${ZAP_STATUS}" == "failure" ]]; then
      ZAP_EXIT_CODE="${exit_code}"
    fi
    write_zap_status_file "${ZAP_STATUS}" "${finished_utc}" "${ZAP_EXIT_CODE}" "${ZAP_MESSAGE}"
    write_status "${WORKSPACE}" "${PHASE_NAME}" "${ZAP_STATUS}" "${ZAP_MESSAGE}"
  fi
}
trap 'exit_code=$?; cleanup_zap "${exit_code}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail_zap() {
  ZAP_MESSAGE="$1"
  die "$1"
}

copy_latest() {
  local source_file="$1"
  local latest_file="$2"
  if [[ -f "${source_file}" ]]; then
    cp "${source_file}" "${latest_file}"
  fi
}

validate_positive_int() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    fail_zap "${name} must be a positive integer: ${value}"
  fi
}

validate_bool() {
  local name="$1"
  local value="$2"
  case "${value}" in
    true|false) ;;
    *) fail_zap "${name} must be true or false: ${value}" ;;
  esac
}

clean_phase_outputs() {
  find "${OUT}" -maxdepth 1 -type f \( \
    -name 'zap-daemon-console-[0-9]*T[0-9]*Z.txt' -o \
    -name 'zap-version-[0-9]*T[0-9]*Z.json' -o \
    -name 'zap-spider-start-[0-9]*T[0-9]*Z.json' -o \
    -name 'zap-spider-status-[0-9]*T[0-9]*Z.json' -o \
    -name 'zap-passive-records-left-[0-9]*T[0-9]*Z.json' -o \
    -name 'zap-alerts-[0-9]*T[0-9]*Z.json' -o \
    -name 'zap-report-[0-9]*T[0-9]*Z.html' -o \
    -name 'zap-daemon-console-latest.txt' -o \
    -name 'zap-version-latest.json' -o \
    -name 'zap-spider-start-latest.json' -o \
    -name 'zap-spider-status-latest.json' -o \
    -name 'zap-passive-records-left-latest.json' -o \
    -name 'zap-alerts-latest.json' -o \
    -name 'zap-report-latest.html' -o \
    -name 'zap-summary.md' -o \
    -name 'zap-findings.json' \
  \) -delete
  rm -f "${WORKSPACE}/status/${PHASE_NAME}.pid"
}

is_pid_alive() {
  local pid="$1"
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" >/dev/null 2>&1
}

check_pid_file() {
  PID_FILE="${WORKSPACE}/status/${PHASE_NAME}.pid"
  if [[ -f "${PID_FILE}" ]]; then
    local old_pid
    old_pid="$(tr -cd '0-9' < "${PID_FILE}" || true)"
    if [[ -n "${old_pid}" ]] && is_pid_alive "${old_pid}"; then
      fail_zap "Phase 6 ZAP PID file exists and process ${old_pid} is alive; stop it or remove ${PID_FILE} after verification."
    fi
    rm -f "${PID_FILE}"
  fi
}

check_port_free() {
  "${PYTHON_BIN:-python3}" - "${ZAP_PORT}" <<'PY'
import socket
import sys
port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(1)
try:
    sys.exit(0 if sock.connect_ex(("127.0.0.1", port)) != 0 else 1)
finally:
    sock.close()
PY
}

extract_json_value() {
  local file="$1"
  local key="$2"
  "${PYTHON_BIN:-python3}" - "${file}" "${key}" <<'PY'
import json
import sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    print("")
    raise SystemExit(0)
value = data
for part in sys.argv[2].split('.'):
    if isinstance(value, dict):
        value = value.get(part, "")
    else:
        value = ""
        break
print(value)
PY
}

wait_for_zap() {
  local deadline=$((SECONDS + ZAP_START_TIMEOUT))
  local attempt=0
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    attempt=$((attempt + 1))
    if zap_get '/JSON/core/view/version/' "${VERSION_JSON}"; then
      copy_latest "${VERSION_JSON}" "${OUT}/zap-version-latest.json"
      [[ "${VERBOSE}" == "true" ]] && printf 'ZAP startup status: ready after %s attempts\n' "${attempt}"
      return 0
    fi
    if ! kill -0 "${ZAP_PID}" >/dev/null 2>&1; then
      fail_zap "ZAP daemon exited before API became ready; review ${CONSOLE_LOG}."
    fi
    [[ "${VERBOSE}" == "true" ]] && printf 'ZAP startup status: waiting (attempt %s)\n' "${attempt}"
    sleep 2
  done
  fail_zap "ZAP API did not become ready within ZAP_START_TIMEOUT=${ZAP_START_TIMEOUT}; review ${CONSOLE_LOG}."
}

run_spider() {
  local encoded_url
  encoded_url="$(urlencode "${LOGIN_URL}")"
  zap_get "/JSON/spider/action/scan/?url=${encoded_url}&recurse=${ZAP_SPIDER_RECURSE}&maxChildren=${ZAP_SPIDER_MAX_CHILDREN}" "${SPIDER_START_JSON}" || fail_zap "Failed to start ZAP spider via API."
  copy_latest "${SPIDER_START_JSON}" "${OUT}/zap-spider-start-latest.json"
  local scan_id
  scan_id="$(extract_json_value "${SPIDER_START_JSON}" scan)"
  [[ -n "${scan_id}" ]] || fail_zap "ZAP spider start response did not include a scan ID."
  local status="0"
  while true; do
    zap_get "/JSON/spider/view/status/?scanId=${scan_id}" "${SPIDER_STATUS_JSON}" || fail_zap "Failed to poll ZAP spider status."
    status="$(extract_json_value "${SPIDER_STATUS_JSON}" status)"
    [[ "${VERBOSE}" == "true" ]] && printf 'ZAP spider progress: %s%%\n' "${status}"
    [[ "${status}" == "100" ]] && break
    sleep 2
  done
  copy_latest "${SPIDER_STATUS_JSON}" "${OUT}/zap-spider-status-latest.json"
}

wait_for_passive_scan() {
  local deadline=$((SECONDS + ZAP_PASSIVE_TIMEOUT))
  local left=""
  while true; do
    zap_get '/JSON/pscan/view/recordsToScan/' "${PASSIVE_RECORDS_JSON}" || fail_zap "Failed to poll ZAP passive scan records."
    left="$(extract_json_value "${PASSIVE_RECORDS_JSON}" recordsToScan)"
    [[ "${VERBOSE}" == "true" ]] && printf 'ZAP passive records remaining: %s\n' "${left}"
    [[ "${left}" == "0" ]] && break
    if [[ "${SECONDS}" -ge "${deadline}" ]]; then
      PASSIVE_TIMED_OUT="true"
      printf 'ZAP passive scan wait timed out with recordsToScan=%s at %s\n' "${left}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${CONSOLE_LOG}"
      break
    fi
    sleep 3
  done
  copy_latest "${PASSIVE_RECORDS_JSON}" "${OUT}/zap-passive-records-left-latest.json"
}

export_zap_outputs() {
  local encoded_url
  encoded_url="$(urlencode "${LOGIN_URL}")"
  zap_get "/JSON/core/view/alerts/?baseurl=${encoded_url}" "${ALERTS_JSON}" || fail_zap "Failed to export ZAP alerts JSON."
  copy_latest "${ALERTS_JSON}" "${OUT}/zap-alerts-latest.json"
  curl -fsS --connect-timeout 2 --max-time 60 "$(zap_api_url '/OTHER/core/other/htmlreport/')" -o "${HTML_REPORT}" || fail_zap "Failed to export ZAP HTML report."
  copy_latest "${HTML_REPORT}" "${OUT}/zap-report-latest.html"
}

write_summary() {
  "${PYTHON_BIN:-python3}" - "${OUT}" "${PHASE_RUN_ID}" "${LOGIN_URL}" "${VERSION_JSON}" "${SPIDER_STATUS_JSON}" "${PASSIVE_RECORDS_JSON}" "${FINDINGS_PATH}" "${SUMMARY_PATH}" "${ZAP_SPIDER_MAX_CHILDREN}" "${ZAP_SPIDER_RECURSE}" "${ZAP_PASSIVE_TIMEOUT}" "${ZAP_STATUS}" "${ZAP_MESSAGE}" "${PASSIVE_TIMED_OUT}" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

out = Path(sys.argv[1])
run_id, target = sys.argv[2], sys.argv[3]
version_path, spider_status_path, passive_path, findings_path, summary_path = [Path(p) for p in sys.argv[4:9]]
max_children, recurse, passive_timeout, status, message, passive_timed_out = sys.argv[9:15]

def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default

version = load_json(version_path, {}).get("version", "unknown")
spider_status = load_json(spider_status_path, {}).get("status", "unknown")
records_left = load_json(passive_path, {}).get("recordsToScan", "unknown")
findings = load_json(findings_path, [])
if not isinstance(findings, list):
    findings = []
severity = Counter(item.get("severity", "unknown") for item in findings if isinstance(item, dict))
statuses = Counter(item.get("status", "unknown") for item in findings if isinstance(item, dict))
notable = [item for item in findings if item.get("severity") in {"high", "medium", "low"}]
info = [item for item in findings if item.get("severity") == "informational"]
raw_names = [
    f"zap-daemon-console-{run_id}.txt",
    f"zap-version-{run_id}.json",
    f"zap-spider-start-{run_id}.json",
    f"zap-spider-status-{run_id}.json",
    f"zap-passive-records-left-{run_id}.json",
    f"zap-alerts-{run_id}.json",
    f"zap-report-{run_id}.html",
    "zap-daemon-console-latest.txt",
    "zap-version-latest.json",
    "zap-spider-start-latest.json",
    "zap-spider-status-latest.json",
    "zap-passive-records-left-latest.json",
    "zap-alerts-latest.json",
    "zap-report-latest.html",
]
with summary_path.open("w", encoding="utf-8") as fh:
    print("# ZAP Passive Assessment Summary\n", file=fh)
    print("## Run\n", file=fh)
    print(f"- target: {target}", file=fh)
    print(f"- run ID: {run_id}", file=fh)
    print(f"- status: {status}", file=fh)
    print(f"- message: {message}", file=fh)
    print(f"- ZAP version: {version}\n", file=fh)
    print("## Spider Settings\n", file=fh)
    print(f"- ZAP_SPIDER_MAX_CHILDREN: {max_children}", file=fh)
    print(f"- ZAP_SPIDER_RECURSE: {recurse}", file=fh)
    print(f"- final spider status: {spider_status}%\n", file=fh)
    print("## Passive Scan Status\n", file=fh)
    print(f"- ZAP_PASSIVE_TIMEOUT: {passive_timeout}", file=fh)
    print(f"- recordsToScan at finish: {records_left}", file=fh)
    print(f"- timed out: {passive_timed_out}\n", file=fh)
    print("## Raw Output Files\n", file=fh)
    for name in raw_names:
        print(f"- {name}" + ("" if (out / name).exists() else " (not present)"), file=fh)
    print("\n## Findings Totals\n", file=fh)
    print("### By severity", file=fh)
    for key in ["high", "medium", "low", "informational"]:
        print(f"- {key}: {severity.get(key, 0)}", file=fh)
    print("\n### By status", file=fh)
    for key in ["confirmed", "observed", "informational", "needs_review"]:
        print(f"- {key}: {statuses.get(key, 0)}", file=fh)
    print("\n## Notable Findings\n", file=fh)
    if notable:
        for item in notable[:20]:
            print(f"- {item.get('severity')}: {item.get('title')} — {item.get('url')}", file=fh)
    else:
        print("- No low-or-higher ZAP passive findings were parsed.", file=fh)
    print("\n## Informational Observations\n", file=fh)
    if info:
        for item in info[:20]:
            print(f"- {item.get('title')} — {item.get('url')}", file=fh)
    else:
        print("- No informational ZAP observations were parsed.", file=fh)
    print("\n## Limitations\n", file=fh)
    print("- This phase starts a local 127.0.0.1 ZAP daemon and performs passive assessment with a limited traditional spider only.", file=fh)
    print("- Active scan, AJAX spider, forced browsing, fuzzing, attacks, and authentication are intentionally not implemented in Phase 6.", file=fh)
    print("- ZAP passive alerts are unvalidated observations and require manual review and de-duplication against earlier phases.", file=fh)
    print("- A passive timeout means partial alerts were exported while queued passive records may remain.", file=fh)
PY
}

print_phase_start() {
  printf '%s starting\n' "${PHASE_NAME}"
  printf 'workspace: %s\n' "${WORKSPACE}"
  printf 'evidence directory: %s\n' "${OUT}"
  printf 'ZAP binary: %s\n' "${ZAP_BIN}"
  printf 'ZAP port: %s\n' "${ZAP_PORT}"
  printf 'target URL: %s\n' "${LOGIN_URL}"
  printf 'spider settings: recurse=%s maxChildren=%s\n' "${ZAP_SPIDER_RECURSE}" "${ZAP_SPIDER_MAX_CHILDREN}"
  printf 'passive timeout: %s\n' "${ZAP_PASSIVE_TIMEOUT}"
  printf 'daemon log path: %s\n' "${CONSOLE_LOG}"
  printf 'monitor command: tail -f "%s"\n' "${CONSOLE_LOG}"
}

ensure_unique_run_id() {
  while [[ -e "${OUT}/zap-daemon-console-${PHASE_RUN_ID}.txt" || -e "${OUT}/zap-alerts-${PHASE_RUN_ID}.json" ]]; do
    sleep 1
    PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
  done
}

validate_workspace "${WORKSPACE}"
OUT="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_DIR="${WORKSPACE}/status"
mkdir -p "${OUT}" "${STATUS_DIR}"
STATUS_READY="true"

if [[ "${CLEAN}" == "true" ]]; then
  clean_phase_outputs
fi

load_env_file "${WORKSPACE}/config/target.env"
require_env_vars LOGIN_URL PROFILE

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi
if [[ -f "${REPO_ROOT}/config/profiles/${PROFILE}.env" ]]; then
  load_env_file "${REPO_ROOT}/config/profiles/${PROFILE}.env"
fi

ZAP_PORT="${ZAP_PORT:-8090}"
ZAP_SPIDER_MAX_CHILDREN="${ZAP_SPIDER_MAX_CHILDREN:-5}"
ZAP_SPIDER_RECURSE="${ZAP_SPIDER_RECURSE:-false}"
ZAP_PASSIVE_TIMEOUT="${ZAP_PASSIVE_TIMEOUT:-600}"
ZAP_START_TIMEOUT="${ZAP_START_TIMEOUT:-120}"
ZAP_AJAX_SPIDER="${ZAP_AJAX_SPIDER:-false}"
ZAP_ACTIVE_SCAN="${ZAP_ACTIVE_SCAN:-false}"

validate_positive_int ZAP_PORT "${ZAP_PORT}"
validate_positive_int ZAP_SPIDER_MAX_CHILDREN "${ZAP_SPIDER_MAX_CHILDREN}"
validate_positive_int ZAP_PASSIVE_TIMEOUT "${ZAP_PASSIVE_TIMEOUT}"
validate_positive_int ZAP_START_TIMEOUT "${ZAP_START_TIMEOUT}"
validate_bool ZAP_SPIDER_RECURSE "${ZAP_SPIDER_RECURSE}"
validate_bool ZAP_AJAX_SPIDER "${ZAP_AJAX_SPIDER}"
validate_bool ZAP_ACTIVE_SCAN "${ZAP_ACTIVE_SCAN}"

if [[ "${ZAP_ACTIVE_SCAN}" == "true" ]]; then
  fail_zap "ZAP active scan is not implemented or allowed in Phase 6. Set ZAP_ACTIVE_SCAN=false."
fi
if [[ "${ZAP_AJAX_SPIDER}" == "true" ]]; then
  fail_zap "ZAP AJAX spider is reserved for a later authenticated/deep implementation. Set ZAP_AJAX_SPIDER=false."
fi

if [[ -n "${ZAP_BIN:-}" ]]; then
  [[ -x "${ZAP_BIN}" ]] || fail_zap "configured ZAP_BIN is not executable: ${ZAP_BIN}"
else
  ZAP_BIN="$(first_existing_command /usr/share/zaproxy/zap.sh zaproxy owasp-zap || true)"
fi
[[ -n "${ZAP_BIN}" ]] || fail_zap "required tool missing: ZAP (set ZAP_BIN in config/tool-paths.env or install /usr/share/zaproxy/zap.sh, zaproxy, or owasp-zap)"

check_pid_file
if ! check_port_free; then
  fail_zap "ZAP port already in use; stop existing ZAP or override ZAP_PORT."
fi

require_command curl
ensure_unique_run_id
CONSOLE_LOG="${OUT}/zap-daemon-console-${PHASE_RUN_ID}.txt"
VERSION_JSON="${OUT}/zap-version-${PHASE_RUN_ID}.json"
SPIDER_START_JSON="${OUT}/zap-spider-start-${PHASE_RUN_ID}.json"
SPIDER_STATUS_JSON="${OUT}/zap-spider-status-${PHASE_RUN_ID}.json"
PASSIVE_RECORDS_JSON="${OUT}/zap-passive-records-left-${PHASE_RUN_ID}.json"
ALERTS_JSON="${OUT}/zap-alerts-${PHASE_RUN_ID}.json"
HTML_REPORT="${OUT}/zap-report-${PHASE_RUN_ID}.html"
SUMMARY_PATH="${OUT}/zap-summary.md"
FINDINGS_PATH="${OUT}/zap-findings.json"
: > "${CONSOLE_LOG}"

print_phase_start
printf 'Starting ZAP daemon at %s\n' "${STARTED_UTC}" >> "${CONSOLE_LOG}"
printf 'Command: %q -daemon -host 127.0.0.1 -port %q -config api.disablekey=true -config database.recoverylog=false\n' "${ZAP_BIN}" "${ZAP_PORT}" >> "${CONSOLE_LOG}"
"${ZAP_BIN}" -daemon -host 127.0.0.1 -port "${ZAP_PORT}" -config api.disablekey=true -config database.recoverylog=false >> "${CONSOLE_LOG}" 2>&1 &
ZAP_PID=$!
ZAP_STARTED="true"
printf '%s\n' "${ZAP_PID}" > "${PID_FILE}"

wait_for_zap
run_spider
wait_for_passive_scan
export_zap_outputs
copy_latest "${CONSOLE_LOG}" "${OUT}/zap-daemon-console-latest.txt"

"${PYTHON_BIN:-python3}" "${REPO_ROOT}/tools/parse-zap.py" --input "${ALERTS_JSON}" --output "${FINDINGS_PATH}"

if [[ "${PASSIVE_TIMED_OUT}" == "true" ]]; then
  ZAP_STATUS="completed_with_warnings"
  ZAP_EXIT_CODE="0"
  ZAP_MESSAGE="ZAP passive timeout reached; partial alerts and report were exported."
else
  ZAP_STATUS="success"
  ZAP_EXIT_CODE="0"
  ZAP_MESSAGE="ZAP passive assessment completed successfully."
fi
write_summary

printf 'final status: %s\n' "${ZAP_STATUS}"
printf 'summary path: %s\n' "${SUMMARY_PATH}"
printf 'findings path: %s\n' "${FINDINGS_PATH}"
printf 'report path: %s\n' "${HTML_REPORT}"
printf 'evidence directory: %s\n' "${OUT}"
