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

tracked_headers=(
  server
  location
  refresh
  strict-transport-security
  content-security-policy
  x-content-type-options
  x-frame-options
  x-xss-protection
  referrer-policy
  permissions-policy
  set-cookie
  cache-control
  pragma
  expires
  access-control-allow-origin
  access-control-allow-credentials
  access-control-allow-methods
  access-control-allow-headers
  vary
)

recommended_headers=(
  x-content-type-options
  referrer-policy
  permissions-policy
)

header_value() {
  local file="$1"
  local header_name="$2"
  if [[ -f "${file}" ]]; then
    awk -v wanted="${header_name}" '
      BEGIN { wanted = tolower(wanted) }
      index($0, ":") {
        name = substr($0, 1, index($0, ":") - 1)
        value = substr($0, index($0, ":") + 1)
        gsub(/^[ \t]+|[ \t\r]+$/, "", value)
        if (tolower(name) == wanted) {
          if (found) {
            found = found "; " value
          } else {
            found = value
          }
        }
      }
      END { if (found) print found }
    ' "${file}"
  fi
}

header_present() {
  local file="$1"
  local header_name="$2"
  [[ -n "$(header_value "${file}" "${header_name}")" ]]
}

hsts_max_age() {
  local value="$1"
  printf '%s\n' "${value}" | grep -Eio 'max-age=[0-9]+' | head -n 1 | cut -d= -f2 || true
}

write_security_header_summaries() {
  local txt_file="${OUT}/security-header-summary.txt"
  local md_file="${OUT}/security-header-summary.md"
  : > "${txt_file}"

  for label in base login; do
    local header_file="${OUT}/${label}-headers-latest.txt"
    local header_name value
    for header_name in "${tracked_headers[@]}"; do
      value="$(header_value "${header_file}" "${header_name}")"
      if [[ -z "${value}" ]]; then
        value="MISSING"
      fi
      printf '%s\t%s\t%s\n' "${label}" "${header_name}" "${value}" >> "${txt_file}"
    done
  done

  {
    printf '# Security Header Summary\n\n'
    for label in base login; do
      local header_file="${OUT}/${label}-headers-latest.txt"
      local hsts_value csp_value cache_value location_value refresh_value max_age missing_recommended present_headers header_name
      hsts_value="$(header_value "${header_file}" "strict-transport-security")"
      csp_value="$(header_value "${header_file}" "content-security-policy")"
      cache_value="$(header_value "${header_file}" "cache-control")"
      location_value="$(header_value "${header_file}" "location")"
      refresh_value="$(header_value "${header_file}" "refresh")"
      max_age="$(hsts_max_age "${hsts_value}")"
      missing_recommended=()
      present_headers=()

      for header_name in "${tracked_headers[@]}"; do
        if header_present "${header_file}" "${header_name}"; then
          present_headers+=("${header_name}")
        fi
      done
      for header_name in "${recommended_headers[@]}"; do
        if ! header_present "${header_file}" "${header_name}"; then
          missing_recommended+=("${header_name}")
        fi
      done

      printf '## %s\n\n' "${label}"
      printf -- '- HTTP status: %s\n' "$(status_line "${header_file}")"
      printf -- '- Present security headers: %s\n' "${present_headers[*]:-none}"
      printf -- '- Missing recommended headers: %s\n' "${missing_recommended[*]:-none}"
      if [[ -n "${hsts_value}" ]]; then
        printf -- '- HSTS: present'
        if [[ -n "${max_age}" ]]; then
          printf ' (max-age=%s)' "${max_age}"
        fi
        printf '\n'
      else
        printf -- '- HSTS: missing\n'
      fi
      printf -- '- Cache-Control: %s\n' "${cache_value:-MISSING}"
      if [[ -n "${csp_value}" ]]; then
        printf -- '- CSP: present\n'
      else
        printf -- '- CSP: missing\n'
      fi
      if [[ -n "${location_value}" ]]; then
        printf -- '- Location header: present\n'
      else
        printf -- '- Location header: missing\n'
      fi
      if [[ -n "${refresh_value}" ]]; then
        printf -- '- Refresh header: present\n\n'
      else
        printf -- '- Refresh header: missing\n\n'
      fi
    done
  } > "${md_file}"
}

write_security_header_summaries

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
- security header markdown summary: security-header-summary.md
- security header text summary: security-header-summary.txt
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
