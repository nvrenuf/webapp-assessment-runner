#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

usage() {
  printf 'Usage: %s --workspace PATH [--yes] [--clean] [--verbose] [--archive]\n' "$0"
}

YES="false"
CLEAN="false"
VERBOSE="false"
ARCHIVE="false"
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
    --archive)
      ARCHIVE="true"
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

PHASE_NAME="phase-9-reporting"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
PHASE_STATUS="failure"
PHASE_MESSAGE="Phase 9 reporting did not complete."
STATUS_READY="false"
REPORT_DIR="${WORKSPACE}/reports"
OUT="${WORKSPACE}/evidence/${PHASE_NAME}"
ARCHIVE_CREATED="false"
CONSOLE_LOG="${OUT}/reporting-console-${PHASE_RUN_ID}.txt"

write_reporting_status() {
  local exit_code="$1"
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc status_file
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${exit_code}" -eq 0 ]]; then
      PHASE_STATUS="success"
    fi
    status_file="${WORKSPACE}/status/${PHASE_NAME}.status"
    mkdir -p "${WORKSPACE}/status"
    cat > "${status_file}" <<STATUS_EOF
STATUS=${PHASE_STATUS}
STARTED_UTC=${STARTED_UTC}
FINISHED_UTC=${finished_utc}
EXIT_CODE=${exit_code}
MESSAGE=$(shell_quote "${PHASE_MESSAGE}")
PHASE_RUN_ID=${PHASE_RUN_ID}
REPORT_DIR=${REPORT_DIR}
ARCHIVE_CREATED=${ARCHIVE_CREATED}
STATUS_EOF
  fi
}
trap 'exit_code=$?; write_reporting_status "${exit_code}"' EXIT

validate_workspace "${WORKSPACE}"
mkdir -p "${REPORT_DIR}" "${OUT}" "${WORKSPACE}/status"
STATUS_READY="true"

clean_phase_9() {
  rm -f \
    "${REPORT_DIR}/executive-summary.md" \
    "${REPORT_DIR}/technical-report.md" \
    "${REPORT_DIR}/findings-final.json" \
    "${REPORT_DIR}/findings-final.csv" \
    "${REPORT_DIR}/evidence-index.md" \
    "${REPORT_DIR}/evidence-index.json" \
    "${REPORT_DIR}/report-metadata.json" \
    "${REPORT_DIR}/report-summary.md" \
    "${REPORT_DIR}/report.md" \
    "${REPORT_DIR}/archive-manifest-latest.json"
  find "${REPORT_DIR}" -maxdepth 1 -type f \( \
    -name 'evidence-package-[0-9]*T[0-9]*Z.tar.gz' -o \
    -name 'archive-manifest-[0-9]*T[0-9]*Z.json' \
  \) -delete
  rm -f "${WORKSPACE}/status/${PHASE_NAME}.status"
  if [[ -d "${OUT}" ]]; then
    find "${OUT}" -maxdepth 1 -type f \( \
      -name 'reporting-console-[0-9]*T[0-9]*Z.txt' -o \
      -name 'reporting-console-latest.txt' -o \
      -name 'normalization-notes-[0-9]*T[0-9]*Z.md' -o \
      -name 'normalization-notes-latest.md' -o \
      -name 'source-findings-[0-9]*T[0-9]*Z.json' -o \
      -name 'source-findings-latest.json' \
    \) -delete
  fi
}

if [[ "${CLEAN}" == "true" ]]; then
  clean_phase_9
fi

: > "${CONSOLE_LOG}"
log_console() {
  printf '%s\n' "$*" | tee -a "${CONSOLE_LOG}"
}

# Load workspace configuration for traceability. Phase 9 does not use these values
# to contact the target.
load_env_file "${WORKSPACE}/config/target.env"
if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi

if [[ "${YES}" != "true" ]]; then
  log_console "Phase 9 is offline-only and will generate reports from existing workspace evidence. Use --yes for non-interactive runbooks."
fi

log_console "Phase: Phase 9 reporting"
log_console "Workspace: ${WORKSPACE}"
log_console "Report directory: ${REPORT_DIR}"
log_console "Evidence directory: ${OUT}"
log_console "Archive requested: ${ARCHIVE}"

cmd=(python3 "${REPO_ROOT}/tools/generate-report.py" --workspace "${WORKSPACE}" --phase-run-id "${PHASE_RUN_ID}")
if [[ "${ARCHIVE}" == "true" ]]; then
  cmd+=(--archive)
fi
if [[ "${VERBOSE}" == "true" ]]; then
  cmd+=(--verbose)
fi

"${cmd[@]}" 2>&1 | tee -a "${CONSOLE_LOG}"

if [[ "${ARCHIVE}" == "true" && -f "${REPORT_DIR}/evidence-package-${PHASE_RUN_ID}.tar.gz" ]]; then
  ARCHIVE_CREATED="true"
fi
PHASE_MESSAGE="Phase 9 reporting completed successfully."
log_console "Final status: success"
log_console "Reports written to: ${REPORT_DIR}"
cp "${CONSOLE_LOG}" "${OUT}/reporting-console-latest.txt"
