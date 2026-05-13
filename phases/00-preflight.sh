#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"
source "${REPO_ROOT}/lib/evidence.sh"
source "${REPO_ROOT}/lib/status.sh"
source "${REPO_ROOT}/lib/logging.sh"

usage() {
  printf 'Usage: %s --workspace PATH [--yes]\n' "$0"
}

YES="false"
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
STATUS_WORKSPACE="${WORKSPACE}"

PHASE_NAME="phase-0-preflight"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PREFLIGHT_MESSAGE="Preflight did not complete."
PREFLIGHT_STATUS="failure"
STATUS_READY="false"

finish_status() {
  local exit_code="$1"
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${exit_code}" -eq 0 && "${PREFLIGHT_STATUS}" != "skipped" ]]; then
      PREFLIGHT_STATUS="success"
    fi
    write_phase_status_file "${STATUS_WORKSPACE}" "${PHASE_NAME}" "${PREFLIGHT_STATUS}" "${STARTED_UTC}" "${finished_utc}" "${exit_code}" "${PREFLIGHT_MESSAGE}"
  fi
}
trap 'exit_code=$?; finish_status "${exit_code}"' EXIT

fail_preflight() {
  PREFLIGHT_MESSAGE="$1"
  die "$1"
}

validate_workspace "${WORKSPACE}"
EVIDENCE_DIR="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_READY="true"
SUMMARY_FILE="${EVIDENCE_DIR}/preflight-summary.md"
WARNINGS=()
PACKAGE_HEALTH="not checked"
APT_CHECK_STATUS="not checked"
APT_SKIP_WARNING='APT dependency check skipped because passwordless sudo is unavailable. Run `sudo apt-get check` manually for full package-health validation.'
DNS_RESULT="not checked"
CONNECTIVITY_RESULT="not checked"
OS_SUMMARY="unknown"

TARGET_ENV="${WORKSPACE}/config/target.env"
CLI_WORKSPACE="${WORKSPACE}"
unset COMPANY_NAME COMPANY_SLUG ENGAGEMENT_NAME TARGET_BASE_URL TARGET_HOST LOGIN_PATH LOGIN_URL ENVIRONMENT PROFILE AUTH_MODE AUTH_ENABLED TESTER RUN_ID WORKSPACE
if ! load_env_file "${TARGET_ENV}"; then
  WORKSPACE="${CLI_WORKSPACE}"
  fail_preflight "could not load target config: ${TARGET_ENV}"
fi
CONFIG_WORKSPACE="${WORKSPACE:-}"
WORKSPACE="${CLI_WORKSPACE}"

required_vars=(
  COMPANY_NAME
  COMPANY_SLUG
  ENGAGEMENT_NAME
  TARGET_BASE_URL
  TARGET_HOST
  LOGIN_PATH
  LOGIN_URL
  ENVIRONMENT
  PROFILE
  AUTH_MODE
  AUTH_ENABLED
  TESTER
  RUN_ID
)

missing_config=()
for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name+x}" || -z "${!var_name}" ]]; then
    missing_config+=("${var_name}")
  fi
done
if [[ -z "${CONFIG_WORKSPACE}" ]]; then
  missing_config+=("WORKSPACE")
fi
if [[ "${#missing_config[@]}" -gt 0 ]]; then
  fail_preflight "missing required target config values: ${missing_config[*]}"
fi

if [[ "$(absolute_path "${CONFIG_WORKSPACE}")" != "${CLI_WORKSPACE}" ]]; then
  fail_preflight "target config WORKSPACE does not match selected workspace"
fi

PROFILE_FILE="${REPO_ROOT}/config/profiles/${PROFILE}.env"
if [[ -f "${PROFILE_FILE}" ]]; then
  load_env_file "${PROFILE_FILE}"
else
  WARNINGS+=("Profile file not found: ${PROFILE_FILE}")
fi

if [[ -f /etc/os-release ]]; then
  cp /etc/os-release "${EVIDENCE_DIR}/os-release.txt"
  OS_SUMMARY="$(grep -E '^PRETTY_NAME=' /etc/os-release | head -n 1 | cut -d= -f2- | tr -d '"' || true)"
fi
uname -a > "${EVIDENCE_DIR}/uname.txt"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "${EVIDENCE_DIR}/utc-date.txt"
df -Pk "${WORKSPACE}" > "${EVIDENCE_DIR}/disk-space.txt"
available_kb="$(df -Pk "${WORKSPACE}" | awk 'NR == 2 {print $4}')"
if [[ -z "${available_kb}" || "${available_kb}" -lt 2097152 ]]; then
  fail_preflight "workspace filesystem needs at least 2GB available"
fi

if ! command -v dpkg >/dev/null 2>&1; then
  fail_preflight "dpkg not found; run preflight from Kali or install/repair dpkg"
fi
if ! command -v apt-get >/dev/null 2>&1; then
  fail_preflight "apt-get not found; run preflight from Kali or repair APT"
fi

set +e
dpkg --audit > "${EVIDENCE_DIR}/dpkg-audit.txt" 2>&1
dpkg_code=$?
set -e

if [[ "${dpkg_code}" -ne 0 || -s "${EVIDENCE_DIR}/dpkg-audit.txt" ]]; then
  fail_preflight "dpkg reports broken packages. Review ${EVIDENCE_DIR}/dpkg-audit.txt and repair packages before assessment."
fi

if command -v sudo >/dev/null 2>&1; then
  set +e
  sudo -n apt-get check > "${EVIDENCE_DIR}/apt-get-check.txt" 2>&1
  apt_code=$?
  set -e
  if [[ "${apt_code}" -eq 0 ]]; then
    APT_CHECK_STATUS="passed"
  elif grep -Eqi 'password|a password is required|sudo: a terminal is required|unable to acquire|could not open lock file|permission denied|are you root' "${EVIDENCE_DIR}/apt-get-check.txt"; then
    APT_CHECK_STATUS="skipped"
    WARNINGS+=("${APT_SKIP_WARNING}")
    {
      printf '\nAPT check was skipped by preflight because passwordless sudo is unavailable.\n'
      printf 'Run `sudo apt-get check` manually for full package-health validation.\n'
    } >> "${EVIDENCE_DIR}/apt-get-check.txt"
  else
    fail_preflight "sudo apt-get check reported package dependency errors. Review ${EVIDENCE_DIR}/apt-get-check.txt and repair APT dependencies before assessment."
  fi
else
  APT_CHECK_STATUS="skipped"
  WARNINGS+=("${APT_SKIP_WARNING}")
  cat > "${EVIDENCE_DIR}/apt-get-check.txt" <<EOF
APT dependency check skipped because sudo is unavailable.
Run \`sudo apt-get check\` manually for full package-health validation.
EOF
fi

if [[ "${APT_CHECK_STATUS}" == "passed" ]]; then
  PACKAGE_HEALTH="healthy"
else
  PACKAGE_HEALTH="dpkg healthy; apt-get check skipped"
fi

TOOL_VERSIONS="${EVIDENCE_DIR}/tool-versions.txt"
TOOL_PATHS="${WORKSPACE}/config/tool-paths.env"
: > "${TOOL_VERSIONS}"
: > "${TOOL_PATHS}"

record_tool() {
  local var_name="$1"
  local display_name="$2"
  local required="$3"
  shift 3
  local path
  if path="$(first_existing_command "$@")"; then
    printf '%s=%s\n' "${var_name}" "$(shell_quote "${path}")" >> "${TOOL_PATHS}"
    {
      printf '%s: %s\n' "${display_name}" "${path}"
      "${path}" --version 2>&1 | head -n 1 || "${path}" -version 2>&1 | head -n 1 || "${path}" -Version 2>&1 | head -n 1 || true
      printf '\n'
    } >> "${TOOL_VERSIONS}"
  else
    printf '%s=\n' "${var_name}" >> "${TOOL_PATHS}"
    printf '%s: missing\n\n' "${display_name}" >> "${TOOL_VERSIONS}"
    if [[ "${required}" == "required" ]]; then
      fail_preflight "required tool missing: ${display_name}"
    fi
    WARNINGS+=("Optional tool missing: ${display_name}")
  fi
}

{
  bash_path="$(first_existing_command bash || true)"
  printf 'bash: %s\n' "${bash_path:-missing}"
  if [[ -n "${bash_path}" ]]; then
    "${bash_path}" --version 2>&1 | head -n 1 || true
  fi
  printf '\n'
} >> "${TOOL_VERSIONS}"
if [[ -z "${bash_path:-}" ]]; then
  fail_preflight "required tool missing: bash"
fi
record_tool CURL_BIN curl required curl
record_tool OPENSSL_BIN openssl required openssl
record_tool NMAP_BIN nmap required nmap
record_tool NIKTO_BIN nikto required nikto
record_tool NUCLEI_BIN nuclei required nuclei
record_tool JQ_BIN jq required jq
record_tool PYTHON_BIN python3 required python3
record_tool TESTSSL_BIN testssl optional testssl testssl.sh
record_tool ZAP_BIN zaproxy optional zaproxy /usr/share/zaproxy/zap.sh owasp-zap

printf '\nPreflight scope confirmation\n'
printf 'Company: %s\n' "${COMPANY_NAME}"
printf 'Engagement: %s\n' "${ENGAGEMENT_NAME}"
printf 'Environment: %s\n' "${ENVIRONMENT}"
printf 'Target: %s\n' "${TARGET_BASE_URL}"
printf 'Login URL: %s\n' "${LOGIN_URL}"
printf 'Profile: %s\n' "${PROFILE}"
printf 'Auth mode: %s\n\n' "${AUTH_MODE}"

if [[ "${YES}" != "true" ]]; then
  read -r -p "Confirm you are authorized to test this target [y/N] " answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    PREFLIGHT_STATUS="skipped"
    PREFLIGHT_MESSAGE="Authorization was not confirmed; target checks were skipped."
    CONNECTIVITY_RESULT="skipped"
    DNS_RESULT="skipped"
    cat > "${SUMMARY_FILE}" <<EOF
# Preflight Summary

- Target: ${TARGET_BASE_URL}
- Profile: ${PROFILE}
- Auth mode: ${AUTH_MODE}
- OS: ${OS_SUMMARY}
- Package health: ${PACKAGE_HEALTH}
- APT dependency check: ${APT_CHECK_STATUS}
- Tool availability: see tool-versions.txt
- DNS result: ${DNS_RESULT}
- Connectivity result: ${CONNECTIVITY_RESULT}
- Warnings: ${WARNINGS[*]:-none}
EOF
    printf 'preflight skipped: authorization not confirmed\n'
    exit 0
  fi
fi

if command -v getent >/dev/null 2>&1; then
  if getent hosts "${TARGET_HOST}" > "${EVIDENCE_DIR}/dns.txt" 2>&1; then
    DNS_RESULT="resolved"
  else
    DNS_RESULT="failed"
    WARNINGS+=("DNS resolution failed for ${TARGET_HOST}")
  fi
elif command -v dig >/dev/null 2>&1; then
  if dig "${TARGET_HOST}" > "${EVIDENCE_DIR}/dns.txt" 2>&1; then
    DNS_RESULT="resolved"
  else
    DNS_RESULT="failed"
    WARNINGS+=("DNS resolution failed for ${TARGET_HOST}")
  fi
else
  DNS_RESULT="not checked"
  WARNINGS+=("Neither getent nor dig is available for DNS resolution")
  printf 'DNS check skipped: getent and dig unavailable\n' > "${EVIDENCE_DIR}/dns.txt"
fi

if curl -k -s -D "${EVIDENCE_DIR}/headers.txt" -o /dev/null --max-time 20 "${LOGIN_URL}"; then
  CONNECTIVITY_RESULT="reachable"
else
  CONNECTIVITY_RESULT="failed"
  fail_preflight "low-impact connectivity check failed for LOGIN_URL"
fi

cat > "${SUMMARY_FILE}" <<EOF
# Preflight Summary

- Target: ${TARGET_BASE_URL}
- Profile: ${PROFILE}
- Auth mode: ${AUTH_MODE}
- OS: ${OS_SUMMARY}
- Package health: ${PACKAGE_HEALTH}
- APT dependency check: ${APT_CHECK_STATUS}
- Tool availability: see tool-versions.txt
- DNS result: ${DNS_RESULT}
- Connectivity result: ${CONNECTIVITY_RESULT}
- Warnings: ${WARNINGS[*]:-none}
EOF

PREFLIGHT_MESSAGE="Preflight completed successfully."
printf 'phase-0-preflight completed\n'
