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

PHASE_NAME="phase-5-nuclei"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
NUCLEI_STATUS="failure"
NUCLEI_MESSAGE="Nuclei phase did not complete."
NUCLEI_EXIT_CODE="1"
STATUS_READY="false"

write_nuclei_status_file() {
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
NUCLEI_RATE=${NUCLEI_RATE:-}
NUCLEI_CONCURRENCY=${NUCLEI_CONCURRENCY:-}
NUCLEI_RETRIES=${NUCLEI_RETRIES:-}
NUCLEI_TIMEOUT=${NUCLEI_TIMEOUT:-}
NUCLEI_TAGS=${NUCLEI_TAGS:-}
NUCLEI_EXCLUDE_TAGS=${NUCLEI_EXCLUDE_TAGS:-}
EOF
}

finish_status() {
  local exit_code="$1"
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${NUCLEI_STATUS}" == "failure" ]]; then
      NUCLEI_EXIT_CODE="${exit_code}"
    fi
    write_nuclei_status_file "${NUCLEI_STATUS}" "${finished_utc}" "${NUCLEI_EXIT_CODE}" "${NUCLEI_MESSAGE}"
    write_status "${WORKSPACE}" "${PHASE_NAME}" "${NUCLEI_STATUS}" "${NUCLEI_MESSAGE}"
  fi
}
trap 'exit_code=$?; finish_status "${exit_code}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail_nuclei() {
  NUCLEI_MESSAGE="$1"
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
    fail_nuclei "${name} must be a positive integer: ${value}"
  fi
}

clean_phase_outputs() {
  find "${OUT}" -maxdepth 1 -type f \( \
    -name 'nuclei-targets-[0-9]*T[0-9]*Z.txt' -o \
    -name 'nuclei-results-[0-9]*T[0-9]*Z.jsonl' -o \
    -name 'nuclei-console-[0-9]*T[0-9]*Z.txt' -o \
    -name 'nuclei-targets-latest.txt' -o \
    -name 'nuclei-results-latest.jsonl' -o \
    -name 'nuclei-console-latest.txt' -o \
    -name 'nuclei-summary.md' -o \
    -name 'nuclei-findings.json' \
  \) -delete
}

ensure_unique_run_id() {
  while [[ -e "${OUT}/nuclei-results-${PHASE_RUN_ID}.jsonl" || -e "${OUT}/nuclei-console-${PHASE_RUN_ID}.txt" || -e "${OUT}/nuclei-targets-${PHASE_RUN_ID}.txt" ]]; do
    sleep 1
    PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
  done
}

print_phase_start() {
  printf '%s starting\n' "${PHASE_NAME}"
  printf 'workspace: %s\n' "${WORKSPACE}"
  printf 'evidence directory: %s\n' "${OUT}"
  printf 'target file: %s\n' "${TARGETS_FILE}"
  printf 'Nuclei binary: %s\n' "${NUCLEI_BIN}"
  printf 'rate: %s\n' "${NUCLEI_RATE}"
  printf 'concurrency: %s\n' "${NUCLEI_CONCURRENCY}"
  printf 'retries: %s\n' "${NUCLEI_RETRIES}"
  printf 'timeout: %s\n' "${NUCLEI_TIMEOUT}"
  printf 'tags: %s\n' "${NUCLEI_TAGS}"
  printf 'exclude tags: %s\n' "${NUCLEI_EXCLUDE_TAGS}"
  printf 'console log path: %s\n' "${CONSOLE_LOG}"
  printf 'monitor command: tail -f "%s"\n' "${CONSOLE_LOG}"
}

write_summary() {
  "${PYTHON_BIN:-python3}" - "${OUT}" "${PHASE_RUN_ID}" "${TARGETS_FILE}" "${JSONL_OUT}" "${CONSOLE_LOG}" "${SUMMARY_PATH}" "${FINDINGS_PATH}" "${NUCLEI_RATE}" "${NUCLEI_CONCURRENCY}" "${NUCLEI_RETRIES}" "${NUCLEI_TIMEOUT}" "${NUCLEI_TAGS}" "${NUCLEI_EXCLUDE_TAGS}" "${NUCLEI_STATUS}" "${NUCLEI_MESSAGE}" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

out, run_id, targets_file, jsonl_out, console_log, summary_path, findings_path = [Path(p) if i in {0,2,3,4,5,6} else p for i, p in enumerate(sys.argv[1:8])]
rate, concurrency, retries, timeout, tags, exclude_tags, status, message = sys.argv[8:16]
try:
    targets = [line.strip() for line in targets_file.read_text(encoding="utf-8").splitlines() if line.strip()]
except FileNotFoundError:
    targets = []
try:
    findings = json.loads(findings_path.read_text(encoding="utf-8"))
except FileNotFoundError:
    findings = []
severity = Counter(item.get("severity", "unknown") for item in findings if isinstance(item, dict))
statuses = Counter(item.get("status", "unknown") for item in findings if isinstance(item, dict))
notable = [item for item in findings if item.get("severity") in {"critical", "high", "medium", "low"}]
info = [item for item in findings if item.get("severity") == "informational"]

with summary_path.open("w", encoding="utf-8") as fh:
    print("# Nuclei Low-Rate Misconfiguration Summary\n", file=fh)
    print("## Run\n", file=fh)
    print(f"- run ID: {run_id}", file=fh)
    print(f"- status: {status}", file=fh)
    print(f"- message: {message}\n", file=fh)
    print("## Target(s)\n", file=fh)
    if targets:
        for target in targets:
            print(f"- {target}", file=fh)
    else:
        print("- none", file=fh)
    print("\n## Profile Settings\n", file=fh)
    print(f"- NUCLEI_RATE: {rate}", file=fh)
    print(f"- NUCLEI_CONCURRENCY: {concurrency}", file=fh)
    print(f"- NUCLEI_RETRIES: {retries}", file=fh)
    print(f"- NUCLEI_TIMEOUT: {timeout}", file=fh)
    print(f"- NUCLEI_TAGS: {tags}", file=fh)
    print(f"- NUCLEI_EXCLUDE_TAGS: {exclude_tags}\n", file=fh)
    print("## Raw Output Files\n", file=fh)
    for path in [targets_file, jsonl_out, console_log, out / "nuclei-targets-latest.txt", out / "nuclei-results-latest.jsonl", out / "nuclei-console-latest.txt"]:
        print(f"- {path.name}" + ("" if path.exists() else " (not present)"), file=fh)
    print("\n## Findings Totals\n", file=fh)
    print("### By severity", file=fh)
    for key in ["critical", "high", "medium", "low", "informational"]:
        print(f"- {key}: {severity.get(key, 0)}", file=fh)
    print("\n### By status", file=fh)
    for key in ["confirmed", "observed", "informational", "needs_review"]:
        print(f"- {key}: {statuses.get(key, 0)}", file=fh)
    print("\n## Notable Findings\n", file=fh)
    if notable:
        for item in notable[:20]:
            print(f"- {item.get('severity')}: {item.get('title')} — {item.get('url')}", file=fh)
    else:
        print("- No low-or-higher Nuclei findings were parsed.", file=fh)
    print("\n## Informational Detections\n", file=fh)
    if info:
        for item in info[:20]:
            print(f"- {item.get('title')} — {item.get('url')}", file=fh)
    else:
        print("- No informational detections were parsed.", file=fh)
    print("\n## Limitations\n", file=fh)
    print("- This phase scans only the configured TARGET_BASE_URL and does not crawl or discover additional targets.", file=fh)
    print("- Nuclei template updates are not run automatically; template currency depends on the operator-managed installation.", file=fh)
    print("- Fuzzing, brute-force, DoS, race, and intrusive templates are excluded by default.", file=fh)
    print("- Scanner findings are unvalidated observations and require manual review and de-duplication against earlier phases.", file=fh)
PY
}

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
counts = Counter(item.get("severity", "unknown") for item in findings if isinstance(item, dict))
for severity in ["critical", "high", "medium", "low", "informational", "unknown"]:
    if counts.get(severity, 0) or severity in {"critical", "high", "medium", "low", "informational"}:
        print(f"{severity}: {counts.get(severity, 0)}")
PY
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
require_env_vars TARGET_BASE_URL PROFILE

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi
if [[ -f "${REPO_ROOT}/config/profiles/${PROFILE}.env" ]]; then
  load_env_file "${REPO_ROOT}/config/profiles/${PROFILE}.env"
fi

NUCLEI_RATE="${NUCLEI_RATE:-1}"
NUCLEI_CONCURRENCY="${NUCLEI_CONCURRENCY:-1}"
NUCLEI_RETRIES="${NUCLEI_RETRIES:-1}"
NUCLEI_TIMEOUT="${NUCLEI_TIMEOUT:-10}"
NUCLEI_TAGS="${NUCLEI_TAGS:-exposure,misconfig,cors,csp,headers,tls,ssl}"
NUCLEI_EXCLUDE_TAGS="${NUCLEI_EXCLUDE_TAGS:-fuzz,bruteforce,dos,race,intrusive}"
validate_positive_int NUCLEI_RATE "${NUCLEI_RATE}"
validate_positive_int NUCLEI_CONCURRENCY "${NUCLEI_CONCURRENCY}"
validate_positive_int NUCLEI_RETRIES "${NUCLEI_RETRIES}"
validate_positive_int NUCLEI_TIMEOUT "${NUCLEI_TIMEOUT}"

if [[ -n "${NUCLEI_BIN:-}" ]]; then
  [[ -x "${NUCLEI_BIN}" ]] || fail_nuclei "configured NUCLEI_BIN is not executable: ${NUCLEI_BIN}"
else
  NUCLEI_BIN="$(first_existing_command nuclei || true)"
fi
[[ -n "${NUCLEI_BIN}" ]] || fail_nuclei "required tool missing: nuclei (set NUCLEI_BIN in config/tool-paths.env or install nuclei)"

ensure_unique_run_id
TARGETS_FILE="${OUT}/nuclei-targets-${PHASE_RUN_ID}.txt"
JSONL_OUT="${OUT}/nuclei-results-${PHASE_RUN_ID}.jsonl"
CONSOLE_LOG="${OUT}/nuclei-console-${PHASE_RUN_ID}.txt"
SUMMARY_PATH="${OUT}/nuclei-summary.md"
FINDINGS_PATH="${OUT}/nuclei-findings.json"

printf '%s\n' "${TARGET_BASE_URL}" > "${TARGETS_FILE}"
: > "${JSONL_OUT}"
: > "${CONSOLE_LOG}"
copy_latest "${TARGETS_FILE}" "${OUT}/nuclei-targets-latest.txt"

print_phase_start
printf 'Starting Nuclei phase at %s\n' "${STARTED_UTC}" >> "${CONSOLE_LOG}"
printf 'Command: %q -l %q -tags %q -exclude-tags %q -rl %q -c %q -retries %q -timeout %q -stats -jsonl -o %q\n' \
  "${NUCLEI_BIN}" "${TARGETS_FILE}" "${NUCLEI_TAGS}" "${NUCLEI_EXCLUDE_TAGS}" "${NUCLEI_RATE}" "${NUCLEI_CONCURRENCY}" "${NUCLEI_RETRIES}" "${NUCLEI_TIMEOUT}" "${JSONL_OUT}" >> "${CONSOLE_LOG}"

set +e
"${NUCLEI_BIN}" -l "${TARGETS_FILE}" -tags "${NUCLEI_TAGS}" -exclude-tags "${NUCLEI_EXCLUDE_TAGS}" -rl "${NUCLEI_RATE}" -c "${NUCLEI_CONCURRENCY}" -retries "${NUCLEI_RETRIES}" -timeout "${NUCLEI_TIMEOUT}" -stats -jsonl -o "${JSONL_OUT}" >> "${CONSOLE_LOG}" 2>&1
nuclei_code=$?
set -e
printf 'Finished Nuclei phase with exit code %s at %s\n' "${nuclei_code}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${CONSOLE_LOG}"
NUCLEI_EXIT_CODE="${nuclei_code}"

copy_latest "${JSONL_OUT}" "${OUT}/nuclei-results-latest.jsonl"
copy_latest "${CONSOLE_LOG}" "${OUT}/nuclei-console-latest.txt"

"${PYTHON_BIN:-python3}" "${REPO_ROOT}/tools/parse-nuclei.py" --input "${JSONL_OUT}" --output "${FINDINGS_PATH}"

if [[ "${nuclei_code}" -eq 0 ]]; then
  NUCLEI_STATUS="success"
  NUCLEI_MESSAGE="Nuclei completed successfully."
elif [[ -s "${JSONL_OUT}" ]]; then
  NUCLEI_STATUS="completed_with_warnings"
  NUCLEI_MESSAGE="Nuclei exited with code ${nuclei_code}, but JSONL output was parsed; review console log."
else
  NUCLEI_STATUS="completed_with_warnings"
  NUCLEI_MESSAGE="Nuclei exited with code ${nuclei_code}; no JSONL findings were parsed. Review console log."
fi
write_summary

printf 'phase-5-nuclei completed (%s)\n' "${NUCLEI_STATUS}"
printf 'status: %s\n' "${NUCLEI_STATUS}"
printf 'summary path: %s\n' "${SUMMARY_PATH}"
printf 'findings path: %s\n' "${FINDINGS_PATH}"
printf 'evidence directory: %s\n' "${OUT}"
printf 'finding count by severity:\n'
while IFS= read -r severity_line; do
  printf '  - %s\n' "${severity_line}"
done < <(severity_counts)

exit 0
