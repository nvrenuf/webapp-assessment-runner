#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"
source "${REPO_ROOT}/lib/evidence.sh"
source "${REPO_ROOT}/lib/status.sh"

usage() {
  printf 'Usage: %s --workspace PATH [--yes] [--clean]\n' "$0"
}

YES="false"
CLEAN="false"
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

PHASE_NAME="phase-2-headers"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
HEADERS_STATUS="failure"
HEADERS_MESSAGE="Header capture did not complete."
STATUS_READY="false"

finish_status() {
  local exit_code="$1"
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${exit_code}" -eq 0 ]]; then
      HEADERS_STATUS="success"
    fi
    write_phase_status_file "${WORKSPACE}" "${PHASE_NAME}" "${HEADERS_STATUS}" "${STARTED_UTC}" "${finished_utc}" "${exit_code}" "${HEADERS_MESSAGE}"
  fi
}
trap 'exit_code=$?; finish_status "${exit_code}"' EXIT

fail_headers() {
  HEADERS_MESSAGE="$1"
  die "$1"
}

validate_workspace "${WORKSPACE}"
OUT="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_READY="true"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
CONSOLE_LOG="${OUT}/phase-2-headers-console-${PHASE_RUN_ID}.txt"

if [[ "${CLEAN}" == "true" ]]; then
  find "${OUT}" -maxdepth 1 -type f \( \
    -name '*-headers-[0-9]*T[0-9]*Z.txt' -o \
    -name '*-body-[0-9]*T[0-9]*Z.html' -o \
    -name '*-redirects-[0-9]*T[0-9]*Z.txt' -o \
    -name 'phase-2-headers-console-[0-9]*T[0-9]*Z.txt' -o \
    -name '*-headers-latest.txt' -o \
    -name '*-body-latest.html' -o \
    -name '*-redirects-latest.txt' \
  \) -delete
fi

log_console() {
  printf '%s\n' "$*" | tee -a "${CONSOLE_LOG}" >/dev/null
}

load_env_file "${WORKSPACE}/config/target.env"
require_env_vars TARGET_BASE_URL LOGIN_URL TARGET_HOST PROFILE

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi

detect_curl() {
  if [[ -n "${CURL_BIN:-}" && -x "${CURL_BIN}" ]]; then
    printf '%s\n' "${CURL_BIN}"
    return 0
  fi
  first_existing_command curl
}

CURL_BIN="$(detect_curl || true)"
[[ -n "${CURL_BIN}" ]] || fail_headers "required tool missing: curl"

copy_latest() {
  local source_file="$1"
  local latest_file="$2"
  if [[ -f "${source_file}" ]]; then
    cp "${source_file}" "${latest_file}"
  fi
}

capture_target() {
  local label="$1"
  local url="$2"
  local headers_file="${OUT}/${label}-headers-${PHASE_RUN_ID}.txt"
  local body_file="${OUT}/${label}-body-${PHASE_RUN_ID}.html"
  local redirects_file="${OUT}/${label}-redirects-${PHASE_RUN_ID}.txt"

  log_console "Capturing ${label}: ${url}"

  set +e
  "${CURL_BIN}" -k -s -D "${headers_file}" -o "${body_file}" --max-time 30 "${url}" >> "${CONSOLE_LOG}" 2>&1
  local capture_code=$?
  "${CURL_BIN}" -k -s -IL --max-time 30 "${url}" > "${redirects_file}" 2>> "${CONSOLE_LOG}"
  local redirects_code=$?
  set -e

  copy_latest "${headers_file}" "${OUT}/${label}-headers-latest.txt"
  copy_latest "${body_file}" "${OUT}/${label}-body-latest.html"
  copy_latest "${redirects_file}" "${OUT}/${label}-redirects-latest.txt"

  if [[ "${capture_code}" -ne 0 ]]; then
    fail_headers "curl header/body capture failed for ${label} (${url})"
  fi
  if [[ "${redirects_code}" -ne 0 ]]; then
    fail_headers "curl redirect capture failed for ${label} (${url})"
  fi
}

capture_target "base" "${TARGET_BASE_URL}"
capture_target "login" "${LOGIN_URL}"

status_line() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    grep -E '^HTTP/' "${file}" | tail -n 1 || true
  fi
}

redirect_lines() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    grep -E '^HTTP/' "${file}" || true
  fi
}

cat > "${OUT}/headers-summary.md" <<EOF
# HTTP Header Capture Summary

## Target URLs

- base: ${TARGET_BASE_URL}
- login: ${LOGIN_URL}

## Files Written

- base headers: base-headers-latest.txt
- base body: base-body-latest.html
- base redirects: base-redirects-latest.txt
- login headers: login-headers-latest.txt
- login body: login-body-latest.html
- login redirects: login-redirects-latest.txt
- console: ${CONSOLE_LOG##*/}

## HTTP Status

- base: $(status_line "${OUT}/base-headers-latest.txt")
- login: $(status_line "${OUT}/login-headers-latest.txt")

## Redirect Chains

### base

$(redirect_lines "${OUT}/base-redirects-latest.txt")

### login

$(redirect_lines "${OUT}/login-redirects-latest.txt")
EOF

HEADERS_MESSAGE="HTTP header and redirect evidence capture completed."
printf 'phase-2-headers completed\n'
