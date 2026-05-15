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
VERBOSE="false"
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

PHASE_NAME="phase-8-authenticated"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
PHASE_STATUS="failure"
PHASE_MESSAGE="Phase 8 authenticated scaffold did not complete."
AUTH_READINESS="unknown"
AUTH_MODE_VALUE="unknown"
AUTH_ENABLED_VALUE="unknown"
STATUS_READY="false"
OUT=""
CONSOLE_LOG=""

write_auth_status() {
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
AUTH_MODE=${AUTH_MODE_VALUE}
AUTH_ENABLED=${AUTH_ENABLED_VALUE}
AUTH_READINESS=${AUTH_READINESS}
STATUS_EOF
  fi
}
trap 'exit_code=$?; write_auth_status "${exit_code}"' EXIT

fail_auth() {
  PHASE_MESSAGE="$1"
  die "$1"
}

validate_workspace "${WORKSPACE}"
OUT="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_READY="true"

clean_phase_8() {
  find "${OUT}" -maxdepth 1 -type f \( \
    -name 'auth-readiness-[0-9]*T[0-9]*Z.json' -o \
    -name 'auth-checklist-[0-9]*T[0-9]*Z.md' -o \
    -name 'auth-notes-[0-9]*T[0-9]*Z.md' -o \
    -name 'auth-console-[0-9]*T[0-9]*Z.txt' -o \
    -name 'auth-readiness-latest.json' -o \
    -name 'auth-checklist-latest.md' -o \
    -name 'auth-notes-latest.md' -o \
    -name 'auth-console-latest.txt' -o \
    -name 'authenticated-summary.md' -o \
    -name 'authenticated-findings.json' \
  \) -delete
}

if [[ "${CLEAN}" == "true" ]]; then
  clean_phase_8
fi

READINESS_FILE="${OUT}/auth-readiness-${PHASE_RUN_ID}.json"
CHECKLIST_FILE="${OUT}/auth-checklist-${PHASE_RUN_ID}.md"
NOTES_FILE="${OUT}/auth-notes-${PHASE_RUN_ID}.md"
CONSOLE_LOG="${OUT}/auth-console-${PHASE_RUN_ID}.txt"
SUMMARY_FILE="${OUT}/authenticated-summary.md"
FINDINGS_FILE="${OUT}/authenticated-findings.json"
: > "${CONSOLE_LOG}"

log_console() {
  printf '%s\n' "$*" | tee -a "${CONSOLE_LOG}"
}

verbose_log() {
  if [[ "${VERBOSE}" == "true" ]]; then
    log_console "$*"
  else
    printf '%s\n' "$*" >> "${CONSOLE_LOG}"
  fi
}

copy_latest() {
  local source_file="$1"
  local latest_file="$2"
  if [[ -f "${source_file}" ]]; then
    cp "${source_file}" "${latest_file}"
  fi
}

join_by() {
  local delimiter="$1"
  shift || true
  local first="true" item
  for item in "$@"; do
    if [[ "${first}" == "true" ]]; then
      printf '%s' "${item}"
      first="false"
    else
      printf '%s%s' "${delimiter}" "${item}"
    fi
  done
}

json_array_from_args() {
  local item first="true"
  printf '['
  for item in "$@"; do
    if [[ "${first}" == "true" ]]; then
      first="false"
    else
      printf ','
    fi
    printf '"%s"' "$(json_escape "${item}")"
  done
  printf ']'
}

append_unique() {
  local array_name="$1"
  local value="$2"
  local existing
  eval "local items=(\"\${${array_name}[@]:-}\")"
  for existing in "${items[@]}"; do
    [[ "${existing}" == "${value}" ]] && return 0
  done
  eval "${array_name}+=(\"\${value}\")"
}

strip_quotes() {
  local value="$1"
  value="${value%%#*}"
  value="${value%$'\r'}"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  if [[ ( "${value}" == \"*\" && "${value}" == *\" ) || ( "${value}" == \'*\' && "${value}" == *\' ) ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "${value}"
}

is_placeholder_value() {
  local key="$1"
  local value_lower="$2"
  if [[ -z "${value_lower}" ]]; then
    return 0
  fi
  case "${value_lower}" in
    placeholder|required|none|false|manual|cookie|header|browser|future|"manual|cookie|header|browser|future"|"placeholder only; do not store real secrets")
      return 0
      ;;
  esac
  if [[ "${key}" == *_PLACEHOLDER && "${value_lower}" == *placeholder* ]]; then
    return 0
  fi
  if [[ "${key}" == "AUTH_NOTES" && "${value_lower}" == *placeholder* && "${value_lower}" == *"do not store real secrets"* ]]; then
    return 0
  fi
  return 1
}

is_secret_named_key() {
  local key="$1"
  [[ "${key}" =~ (^|_)(PASSWORD|TOKEN|COOKIE|SESSION|JWT|API_KEY)($|_) ]]
}

looks_like_secret_value() {
  local value="$1"
  local value_lower="$2"
  local compact
  compact="$(printf '%s' "${value}" | tr -d '[:space:]')"
  [[ "${value_lower}" == bearer\ * ]] && return 0
  [[ "${value_lower}" == *sessionid=* || "${value_lower}" == *cookie:* || "${value_lower}" == *set-cookie:* ]] && return 0
  [[ "${value}" =~ ^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] && return 0
  [[ "${value}" =~ ^[A-Za-z0-9_=-]*\.[A-Za-z0-9_=-]*\.[A-Za-z0-9_=-]*$ && ${#value} -ge 40 ]] && return 0
  [[ "${value}" =~ ^[A-Za-z0-9+/=]{40,}$ ]] && return 0
  [[ "${value}" =~ ^[A-Fa-f0-9]{32,}$ ]] && return 0
  [[ "${compact}" =~ ^[A-Za-z0-9_-]{48,}$ ]] && return 0
  [[ "${value}" =~ (sk|pk|api|key|token|secret|bearer)_[A-Za-z0-9_-]{16,} ]] && return 0
  return 1
}

has_auth_key() {
  local wanted="$1"
  local key
  for key in "${AUTH_KEYS[@]:-}"; do
    [[ "${key}" == "${wanted}" ]] && return 0
  done
  return 1
}

analyze_auth_env() {
  local auth_file="$1"
  local line key raw_value value value_lower
  AUTH_KEYS=()
  MISSING_PLACEHOLDERS=()
  WARNING_VARS=()
  FAILURE_VARS=()
  SECRET_VARS=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    line="${line#export }"
    if [[ "${line}" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      raw_value="${BASH_REMATCH[2]}"
      value="$(strip_quotes "${raw_value}")"
      value_lower="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
      AUTH_KEYS+=("${key}")
      if ! is_placeholder_value "${key}" "${value_lower}"; then
        if is_secret_named_key "${key}"; then
          append_unique FAILURE_VARS "${key}"
          append_unique SECRET_VARS "${key}"
        elif looks_like_secret_value "${value}" "${value_lower}"; then
          append_unique WARNING_VARS "${key}"
          append_unique SECRET_VARS "${key}"
        fi
      fi
    fi
  done < "${auth_file}"

  local required_key
  for required_key in \
    AUTH_LOGIN_METHOD \
    AUTH_USERNAME_PLACEHOLDER \
    AUTH_PASSWORD_PLACEHOLDER \
    AUTH_TEST_USER_1 \
    AUTH_TEST_USER_2 \
    AUTH_TEST_TENANT_1 \
    AUTH_TEST_TENANT_2 \
    AUTH_SESSION_COOKIE_PLACEHOLDER \
    AUTH_CSRF_TOKEN_PLACEHOLDER \
    AUTH_BEARER_TOKEN_PLACEHOLDER \
    AUTH_NOTES; do
    if ! has_auth_key "${required_key}"; then
      MISSING_PLACEHOLDERS+=("${required_key}")
    fi
  done
}

load_env_file "${WORKSPACE}/config/target.env"
require_env_vars TARGET_BASE_URL PROFILE
AUTH_MODE_VALUE="${AUTH_MODE:-none}"
AUTH_ENABLED_VALUE="${AUTH_ENABLED:-false}"

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi

PROFILE_FILE="${REPO_ROOT}/config/profiles/${PROFILE}.env"
if [[ -f "${PROFILE_FILE}" ]]; then
  load_env_file "${PROFILE_FILE}"
fi

AUTH_ENV_PATH="${WORKSPACE}/config/auth.env"
AUTH_ENV_EXISTS="false"
[[ -f "${AUTH_ENV_PATH}" ]] && AUTH_ENV_EXISTS="true"

log_console "Phase: Phase 8 authenticated testing scaffold"
log_console "Workspace: ${WORKSPACE}"
log_console "Evidence directory: ${OUT}"
log_console "Auth mode: ${AUTH_MODE_VALUE}"
log_console "Auth enabled: ${AUTH_ENABLED_VALUE}"
log_console "auth.env exists: ${AUTH_ENV_EXISTS}"
log_console "Safety warning: no authentication, form submission, crawling, fuzzing, credentialed API calls, or authorization testing is performed by this scaffold."
verbose_log "Console log path: ${CONSOLE_LOG}"

AUTH_ENABLED_NORMALIZED="$(printf '%s' "${AUTH_ENABLED_VALUE}" | tr '[:upper:]' '[:lower:]')"
AUTH_MODE_NORMALIZED="$(printf '%s' "${AUTH_MODE_VALUE}" | tr '[:upper:]' '[:lower:]')"
AUTH_IS_ENABLED="false"
if [[ "${AUTH_MODE_NORMALIZED}" != "none" && "${AUTH_ENABLED_NORMALIZED}" != "false" ]]; then
  if [[ "${AUTH_MODE_NORMALIZED}" == "placeholder" || "${AUTH_ENABLED_NORMALIZED}" == "true" ]]; then
    AUTH_IS_ENABLED="true"
  fi
fi

WARNINGS=()
FUTURE_WARNINGS=()
FINDING_TITLE=""
FINDING_SEVERITY="informational"
FINDING_STATUS="informational"
FINDING_CATEGORY="auth"
FINDING_EVIDENCE=""
FINDING_DESCRIPTION=""
FINDING_RECOMMENDATION=""
EXIT_AFTER_OUTPUT="0"

if [[ "${AUTH_IS_ENABLED}" != "true" ]]; then
  AUTH_READINESS="not_enabled"
  PHASE_MESSAGE="Authenticated testing is not enabled for this workspace."
  FINDING_TITLE="Authenticated testing not enabled"
  FINDING_SEVERITY="informational"
  FINDING_STATUS="not_enabled"
  FINDING_CATEGORY="auth"
  FINDING_EVIDENCE="AUTH_MODE=${AUTH_MODE_VALUE}; AUTH_ENABLED=${AUTH_ENABLED_VALUE}. No authenticated testing was attempted."
  FINDING_DESCRIPTION="Phase 8 determined that authenticated testing is disabled for this workspace."
  FINDING_RECOMMENDATION="Use AUTH_MODE=placeholder and AUTH_ENABLED=true only after written authorization and placeholder planning inputs are available."
elif [[ "${AUTH_ENV_EXISTS}" != "true" ]]; then
  AUTH_READINESS="missing_auth_env"
  PHASE_MESSAGE="Authenticated testing is enabled, but config/auth.env is missing."
  FINDING_TITLE="Authenticated testing configuration missing"
  FINDING_SEVERITY="low"
  FINDING_STATUS="needs_input"
  FINDING_CATEGORY="configuration"
  FINDING_EVIDENCE="config/auth.env was not present. No authenticated testing was attempted."
  FINDING_DESCRIPTION="Phase 8 requires placeholder-only auth planning inputs before future authenticated testing can be prepared."
  FINDING_RECOMMENDATION="Create config/auth.env with placeholder-only variables; do not store real credentials, cookies, bearer tokens, API keys, JWTs, or session material."
else
  analyze_auth_env "${AUTH_ENV_PATH}"
  if [[ "${#FAILURE_VARS[@]}" -gt 0 || "${#WARNING_VARS[@]}" -gt 0 ]]; then
    AUTH_READINESS="unsafe_secret_detected"
    if [[ "${#FAILURE_VARS[@]}" -gt 0 ]]; then
      PHASE_MESSAGE="Possible real secret stored in auth config; remove non-placeholder values before continuing."
      EXIT_AFTER_OUTPUT="1"
    else
      PHASE_MESSAGE="Possible real secret-like value stored in auth config; review placeholder-only requirements."
    fi
    FINDING_TITLE="Possible real secret stored in auth config"
    FINDING_SEVERITY="medium"
    FINDING_STATUS="observed"
    FINDING_CATEGORY="configuration"
    FINDING_EVIDENCE="Possible secret variable names: $(join_by ', ' "${SECRET_VARS[@]}"). Values were intentionally not recorded."
    FINDING_DESCRIPTION="Phase 8 detected auth.env variables that appear to contain real secret material instead of placeholder-only planning values."
    FINDING_RECOMMENDATION="Remove real credentials, cookies, bearer tokens, API keys, JWTs, and session material from auth.env. Use approved local secret handling only after future authenticated automation is implemented."
    for key in "${SECRET_VARS[@]}"; do
      WARNINGS+=("Possible secret-like value detected in ${key}; value suppressed")
    done
  else
    AUTH_READINESS="placeholder_ready"
    PHASE_MESSAGE="Authenticated testing scaffold ready with placeholder-only configuration."
    FINDING_TITLE="Authenticated testing scaffold ready"
    FINDING_SEVERITY="informational"
    FINDING_STATUS="observed"
    FINDING_CATEGORY="auth"
    FINDING_EVIDENCE="config/auth.env exists and no obvious real secrets were detected. Values were intentionally not recorded."
    FINDING_DESCRIPTION="Phase 8 prepared authenticated-testing planning outputs without authenticating to the target."
    FINDING_RECOMMENDATION="Before future authenticated testing, obtain written authorization, approved test accounts, role and tenant mappings, and safe secret-handling procedures."
  fi

  if [[ "${AUTH_READINESS}" == "placeholder_ready" ]]; then
    if ! has_auth_key "AUTH_TEST_USER_2"; then
      FUTURE_WARNINGS+=("AUTH_TEST_USER_2 missing; future horizontal authorization checks need two same-tenant users")
    fi
    if ! has_auth_key "AUTH_TEST_TENANT_2"; then
      FUTURE_WARNINGS+=("AUTH_TEST_TENANT_2 missing; future tenant-isolation checks need users in two tenants")
    fi
  fi
  for key in "${MISSING_PLACEHOLDERS[@]:-}"; do
    WARNINGS+=("Placeholder key missing: ${key}")
  done
fi

cat > "${CHECKLIST_FILE}" <<'CHECKLIST_EOF'
# Authenticated Testing Checklist

## Required authorization

- Confirm written authorization for authenticated testing before any credentialed activity.
- Confirm target environment, allowed windows, approved workflows, rate limits, and side-effect boundaries.
- Obtain explicit written approval before testing destructive workflows.

## Required test accounts

- Use dedicated test accounts only.
- Do not use employee, customer, production administrator, or shared personal accounts.
- Store real credentials only through an approved local secret-handling process after future support exists.

## Minimum account model

- One normal test user for basic authenticated checks.
- Two users in the same tenant for horizontal authorization checks.
- Two users in different tenants for tenant isolation checks.
- At least one lower-privilege and one higher-privilege role for vertical authorization checks.
- Explicit written approval before testing destructive workflows.

## Session handling

- Identify expected session cookie names and lifetimes without storing cookie values in Git.
- Plan checks for cookie flags, idle timeout, absolute timeout, concurrent sessions, and session fixation only after authorization.

## CSRF handling

- Identify state-changing workflows and CSRF token locations.
- Plan token validation checks only after safe credential and request handling exists.

## IDOR checks

- Define approved object types, user relationships, and expected access boundaries.
- Use two approved same-tenant users before testing horizontal authorization.

## Tenant isolation checks

- Define tenant identifiers, approved tenant pairs, and expected isolation boundaries.
- Use approved users from different tenants before testing cross-tenant behavior.

## Role/permission checks

- Map lower-privilege and higher-privilege roles.
- Document expected allowed and denied actions per role before testing.

## API route inventory

- Build a route inventory from approved documentation, browser observation, or passive sources.
- Do not crawl or call APIs using credentials until future authenticated automation is implemented and authorized.

## File upload/download checks, if authorized

- Confirm allowed file types, size limits, malware-safety expectations, and storage locations.
- Avoid destructive or unsafe files unless specifically approved.

## Logout/session invalidation

- Plan checks for logout behavior, token invalidation, back-button caching, and session reuse.
- Do not capture or replay real sessions in scaffold mode.

## Evidence handling

- Keep evidence inside the selected workspace.
- Redact sensitive data before sharing.
- Record variable names and planning gaps only; never record secret values.

## What must not be stored in Git

- Real usernames paired with passwords.
- Passwords, bearer tokens, API keys, JWTs, session cookies, CSRF tokens, HAR files, session files, or authenticated browser profiles.
- Customer data, screenshots with sensitive content, or generated evidence outside the workspace.

## Future automation notes

- Future authenticated automation must add safe secret loading, redaction, scope gates, and explicit per-workflow approval.
- Future checks should remain low-impact by default and must not include brute force, denial of service, race testing, fuzzing, credential stuffing, or broad crawling.
CHECKLIST_EOF

cat > "${NOTES_FILE}" <<NOTES_EOF
# Phase 8 Authenticated Testing Notes

Phase 8 is currently a safe scaffold. It did not authenticate, submit forms, crawl, fuzz, brute force, call APIs using credentials, or perform authorization testing.

Supported placeholder keys for config/auth.env:

\`\`\`bash
AUTH_LOGIN_METHOD="manual|cookie|header|browser|future"
AUTH_USERNAME_PLACEHOLDER="required"
AUTH_PASSWORD_PLACEHOLDER="required"
AUTH_TEST_USER_1="placeholder"
AUTH_TEST_USER_2="placeholder"
AUTH_TEST_TENANT_1="placeholder"
AUTH_TEST_TENANT_2="placeholder"
AUTH_SESSION_COOKIE_PLACEHOLDER="placeholder"
AUTH_CSRF_TOKEN_PLACEHOLDER="placeholder"
AUTH_BEARER_TOKEN_PLACEHOLDER="placeholder"
AUTH_NOTES="placeholder only; do not store real secrets"
\`\`\`
NOTES_EOF

cat > "${SUMMARY_FILE}" <<SUMMARY_EOF
# Authenticated Testing Summary

- Auth mode: ${AUTH_MODE_VALUE}
- Auth enabled: ${AUTH_ENABLED_VALUE}
- Readiness status: ${AUTH_READINESS}
- auth.env exists: ${AUTH_ENV_EXISTS}
- Checklist: ${CHECKLIST_FILE}

## Warnings
SUMMARY_EOF
if [[ "${#WARNINGS[@]}" -eq 0 && "${#FUTURE_WARNINGS[@]}" -eq 0 ]]; then
  printf '\n- None.\n' >> "${SUMMARY_FILE}"
else
  for warning in "${WARNINGS[@]:-}" "${FUTURE_WARNINGS[@]:-}"; do
    [[ -n "${warning}" ]] && printf -- '- %s.\n' "${warning}" >> "${SUMMARY_FILE}"
  done
fi
cat >> "${SUMMARY_FILE}" <<'SUMMARY_EOF'

## Future testing prerequisites

- Written authorization for authenticated testing scope, timing, roles, tenants, and side-effect boundaries.
- Dedicated test accounts matching the minimum account model.
- Approved local secret-handling that does not store secrets in Git, status files, JSON, summaries, or console logs.
- Route/workflow inventory and expected authorization decisions before testing.

## Limitations

- No authentication was performed.
- No forms were submitted.
- No crawling, fuzzing, brute force, credential stuffing, denial of service, race testing, or active authorization checks were performed.
- Scaffold findings are informational, low, or medium only and do not confirm application vulnerabilities.
SUMMARY_EOF

cat > "${READINESS_FILE}" <<READINESS_EOF
{
  "phase": "phase-8-authenticated",
  "phase_run_id": "$(json_escape "${PHASE_RUN_ID}")",
  "started_utc": "$(json_escape "${STARTED_UTC}")",
  "auth_mode": "$(json_escape "${AUTH_MODE_VALUE}")",
  "auth_enabled": "$(json_escape "${AUTH_ENABLED_VALUE}")",
  "auth_env_exists": ${AUTH_ENV_EXISTS},
  "readiness": "$(json_escape "${AUTH_READINESS}")",
  "warning_variables": $(json_array_from_args "${SECRET_VARS[@]:-}"),
  "missing_placeholder_keys": $(json_array_from_args "${MISSING_PLACEHOLDERS[@]:-}"),
  "future_warnings": $(json_array_from_args "${FUTURE_WARNINGS[@]:-}"),
  "secrets_redacted": true,
  "authentication_performed": false,
  "crawl_performed": false,
  "active_authorization_testing_performed": false
}
READINESS_EOF

cat > "${FINDINGS_FILE}" <<FINDINGS_EOF
[
  {
    "id": "AUTH-001",
    "title": "$(json_escape "${FINDING_TITLE}")",
    "severity": "$(json_escape "${FINDING_SEVERITY}")",
    "status": "$(json_escape "${FINDING_STATUS}")",
    "source": "phase-8-authenticated",
    "category": "$(json_escape "${FINDING_CATEGORY}")",
    "url": "$(json_escape "${TARGET_BASE_URL}")",
    "evidence": "$(json_escape "${FINDING_EVIDENCE}")",
    "description": "$(json_escape "${FINDING_DESCRIPTION}")",
    "recommendation": "$(json_escape "${FINDING_RECOMMENDATION}")"
  }
]
FINDINGS_EOF

copy_latest "${READINESS_FILE}" "${OUT}/auth-readiness-latest.json"
copy_latest "${CHECKLIST_FILE}" "${OUT}/auth-checklist-latest.md"
copy_latest "${NOTES_FILE}" "${OUT}/auth-notes-latest.md"
log_console "Final status: $([[ "${EXIT_AFTER_OUTPUT}" == "0" ]] && printf 'success' || printf 'failure')"
log_console "Readiness: ${AUTH_READINESS}"
log_console "Summary path: ${SUMMARY_FILE}"
log_console "Findings path: ${FINDINGS_FILE}"
log_console "Checklist path: ${CHECKLIST_FILE}"
log_console "Evidence directory: ${OUT}"
copy_latest "${CONSOLE_LOG}" "${OUT}/auth-console-latest.txt"

if [[ "${EXIT_AFTER_OUTPUT}" != "0" ]]; then
  fail_auth "${PHASE_MESSAGE}"
fi
