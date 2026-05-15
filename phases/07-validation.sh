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

PHASE_NAME="phase-7-validation"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PHASE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
VALIDATION_STATUS="failure"
VALIDATION_MESSAGE="Phase 7 validation did not complete."
STATUS_READY="false"
OUT=""
CONSOLE_LOG=""

write_validation_status() {
  local exit_code="$1"
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc status_file
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${exit_code}" -eq 0 ]]; then
      VALIDATION_STATUS="success"
    fi
    status_file="${WORKSPACE}/status/${PHASE_NAME}.status"
    mkdir -p "${WORKSPACE}/status"
    cat > "${status_file}" <<STATUS_EOF
STATUS=${VALIDATION_STATUS}
STARTED_UTC=${STARTED_UTC}
FINISHED_UTC=${finished_utc}
EXIT_CODE=${exit_code}
MESSAGE=$(shell_quote "${VALIDATION_MESSAGE}")
PHASE_RUN_ID=${PHASE_RUN_ID}
STATUS_EOF
  fi
}
trap 'exit_code=$?; write_validation_status "${exit_code}"' EXIT

fail_validation() {
  VALIDATION_MESSAGE="$1"
  die "$1"
}

validate_workspace "${WORKSPACE}"
OUT="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_READY="true"

clean_phase_7() {
  find "${OUT}" -maxdepth 1 -type f \( \
    -name 'validation-login-headers-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-login-body-[0-9]*T[0-9]*Z.html' -o \
    -name 'validation-cors-headers-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-base-redirects-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-login-redirects-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-openssl-tls12-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-openssl-tls13-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-openssl-null-anon-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-console-[0-9]*T[0-9]*Z.txt' -o \
    -name 'validation-login-headers-latest.txt' -o \
    -name 'validation-login-body-latest.html' -o \
    -name 'validation-cors-headers-latest.txt' -o \
    -name 'validation-base-redirects-latest.txt' -o \
    -name 'validation-login-redirects-latest.txt' -o \
    -name 'validation-openssl-tls12-latest.txt' -o \
    -name 'validation-openssl-tls13-latest.txt' -o \
    -name 'validation-openssl-null-anon-latest.txt' -o \
    -name 'validation-console-latest.txt' -o \
    -name 'validation-summary.md' -o \
    -name 'validation-findings.json' \
  \) -delete
}

if [[ "${CLEAN}" == "true" ]]; then
  clean_phase_7
fi

LOGIN_HEADERS="${OUT}/validation-login-headers-${PHASE_RUN_ID}.txt"
LOGIN_BODY="${OUT}/validation-login-body-${PHASE_RUN_ID}.html"
CORS_HEADERS="${OUT}/validation-cors-headers-${PHASE_RUN_ID}.txt"
BASE_REDIRECTS="${OUT}/validation-base-redirects-${PHASE_RUN_ID}.txt"
LOGIN_REDIRECTS="${OUT}/validation-login-redirects-${PHASE_RUN_ID}.txt"
OPENSSL_TLS12="${OUT}/validation-openssl-tls12-${PHASE_RUN_ID}.txt"
OPENSSL_TLS13="${OUT}/validation-openssl-tls13-${PHASE_RUN_ID}.txt"
OPENSSL_NULL="${OUT}/validation-openssl-null-anon-${PHASE_RUN_ID}.txt"
CONSOLE_LOG="${OUT}/validation-console-${PHASE_RUN_ID}.txt"
SUMMARY_FILE="${OUT}/validation-summary.md"
FINDINGS_FILE="${OUT}/validation-findings.json"
FINDINGS_TSV="${OUT}/.validation-findings-${PHASE_RUN_ID}.tsv"
: > "${CONSOLE_LOG}"
: > "${FINDINGS_TSV}"

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

load_env_file "${WORKSPACE}/config/target.env"
require_env_vars TARGET_BASE_URL LOGIN_URL TARGET_HOST PROFILE

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi

PROFILE_FILE="${REPO_ROOT}/config/profiles/${PROFILE}.env"
if [[ -f "${PROFILE_FILE}" ]]; then
  load_env_file "${PROFILE_FILE}"
fi

detect_bin() {
  local configured="$1"
  shift
  if [[ -n "${configured}" && -x "${configured}" ]]; then
    printf '%s\n' "${configured}"
    return 0
  fi
  first_existing_command "$@"
}

CURL_BIN="$(detect_bin "${CURL_BIN:-}" curl || true)"
OPENSSL_BIN="$(detect_bin "${OPENSSL_BIN:-}" openssl || true)"
[[ -n "${CURL_BIN}" ]] || fail_validation "required tool missing: curl"
[[ -n "${OPENSSL_BIN}" ]] || fail_validation "required tool missing: openssl"

log_console "Phase: Phase 7 final validation"
log_console "Workspace: ${WORKSPACE}"
log_console "Evidence directory: ${OUT}"
log_console "Target base URL: ${TARGET_BASE_URL}"
log_console "Login URL: ${LOGIN_URL}"
log_console "curl binary: ${CURL_BIN}"
log_console "openssl binary: ${OPENSSL_BIN}"
log_console "Console log path: ${CONSOLE_LOG}"

set +e
"${CURL_BIN}" -k -sS -L -D "${LOGIN_HEADERS}" -o "${LOGIN_BODY}" --max-time 30 "${LOGIN_URL}" >> "${CONSOLE_LOG}" 2>&1
login_capture_code=$?
"${CURL_BIN}" -k -sS -H "Origin: https://evil.example.com" -D "${CORS_HEADERS}" -o /dev/null --max-time 30 "${LOGIN_URL}" >> "${CONSOLE_LOG}" 2>&1
cors_capture_code=$?
"${CURL_BIN}" -k -sS -IL --max-time 30 "${TARGET_BASE_URL}" > "${BASE_REDIRECTS}" 2>> "${CONSOLE_LOG}"
base_redirect_code=$?
"${CURL_BIN}" -k -sS -IL --max-time 30 "${LOGIN_URL}" > "${LOGIN_REDIRECTS}" 2>> "${CONSOLE_LOG}"
login_redirect_code=$?
"${OPENSSL_BIN}" s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -tls1_2 </dev/null > "${OPENSSL_TLS12}" 2>&1
tls12_code=$?
"${OPENSSL_BIN}" s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -tls1_3 </dev/null > "${OPENSSL_TLS13}" 2>&1
tls13_code=$?
"${OPENSSL_BIN}" s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -cipher 'NULL:eNULL:aNULL' -tls1_2 </dev/null > "${OPENSSL_NULL}" 2>&1
null_code=$?
set -e

copy_latest "${LOGIN_HEADERS}" "${OUT}/validation-login-headers-latest.txt"
copy_latest "${LOGIN_BODY}" "${OUT}/validation-login-body-latest.html"
copy_latest "${CORS_HEADERS}" "${OUT}/validation-cors-headers-latest.txt"
copy_latest "${BASE_REDIRECTS}" "${OUT}/validation-base-redirects-latest.txt"
copy_latest "${LOGIN_REDIRECTS}" "${OUT}/validation-login-redirects-latest.txt"
copy_latest "${OPENSSL_TLS12}" "${OUT}/validation-openssl-tls12-latest.txt"
copy_latest "${OPENSSL_TLS13}" "${OUT}/validation-openssl-tls13-latest.txt"
copy_latest "${OPENSSL_NULL}" "${OUT}/validation-openssl-null-anon-latest.txt"
copy_latest "${CONSOLE_LOG}" "${OUT}/validation-console-latest.txt"

if [[ "${login_capture_code}" -ne 0 ]]; then
  fail_validation "curl login header/body capture failed for ${LOGIN_URL}"
fi
if [[ "${cors_capture_code}" -ne 0 ]]; then
  fail_validation "curl CORS header capture failed for ${LOGIN_URL}"
fi
if [[ "${base_redirect_code}" -ne 0 ]]; then
  fail_validation "curl redirect capture failed for ${TARGET_BASE_URL}"
fi
if [[ "${login_redirect_code}" -ne 0 ]]; then
  fail_validation "curl redirect capture failed for ${LOGIN_URL}"
fi

final_status_line() {
  local file="$1"
  awk '/^HTTP\// { status=$0 } END { if (status) print status }' "${file}" 2>/dev/null || true
}

final_status_code() {
  local file="$1"
  final_status_line "${file}" | awk '{ gsub(/\r/, "", $2); print $2 }'
}

header_value() {
  local file="$1"
  local header_name="$2"
  awk -v wanted="${header_name}" '
    BEGIN { wanted = tolower(wanted); found = "" }
    /^HTTP\// { found = ""; next }
    index($0, ":") {
      name = substr($0, 1, index($0, ":") - 1)
      value = substr($0, index($0, ":") + 1)
      gsub(/^[ \t]+|[ \t\r]+$/, "", value)
      if (tolower(name) == wanted) {
        if (found != "") found = found "; " value
        else found = value
      }
    }
    END { if (found != "") print found }
  ' "${file}" 2>/dev/null || true
}

hsts_max_age() {
  local value="$1"
  printf '%s\n' "${value}" | awk 'BEGIN{IGNORECASE=1} match($0,/max-age=[0-9]+/) { print substr($0, RSTART + 8, RLENGTH - 8); exit }'
}

csp_directive() {
  local csp="$1"
  local wanted="$2"
  printf '%s\n' "${csp}" | awk -v wanted="${wanted}" '
    BEGIN { FS = ";"; wanted = tolower(wanted) }
    {
      for (i = 1; i <= NF; i++) {
        directive = $i
        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", directive)
        name = tolower(directive)
        sub(/[ \t].*$/, "", name)
        if (name == wanted) {
          value = directive
          sub(/^[^ \t]+[ \t]*/, "", value)
          if (value == directive) value = ""
          print value
          exit
        }
      }
    }
  '
}

openssl_cipher() {
  local file="$1"
  {
    awk '/^[[:space:]]*Cipher[[:space:]]*:/ { sub(/^[[:space:]]*Cipher[[:space:]]*:[[:space:]]*/, ""); print }' "${file}" 2>/dev/null
    awk '/Cipher is / { sub(/^.*Cipher is /, ""); print }' "${file}" 2>/dev/null
  } | tail -n 1
}

append_joined() {
  local sep="$1"
  shift
  local out=""
  local item
  for item in "$@"; do
    if [[ -n "${out}" ]]; then
      out+="${sep}${item}"
    else
      out="${item}"
    fi
  done
  printf '%s' "${out}"
}

FINDING_COUNT=0
add_finding() {
  local title="$1"
  local severity="$2"
  local status="$3"
  local category="$4"
  local url="$5"
  local evidence="$6"
  local description="$7"
  local recommendation="$8"
  FINDING_COUNT=$((FINDING_COUNT + 1))
  local id
  id="$(printf 'VALIDATION-%03d' "${FINDING_COUNT}")"
  printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
    "${id}" "${title}" "${severity}" "${status}" "${category}" "${url}" "${evidence}" "${description}" "${recommendation}" >> "${FINDINGS_TSV}"
}

LOGIN_STATUS="$(final_status_code "${LOGIN_HEADERS}")"
CSP="$(header_value "${LOGIN_HEADERS}" "content-security-policy")"
XCTO="$(header_value "${LOGIN_HEADERS}" "x-content-type-options")"
REFPOL="$(header_value "${LOGIN_HEADERS}" "referrer-policy")"
PERMPOL="$(header_value "${LOGIN_HEADERS}" "permissions-policy")"
HSTS="$(header_value "${LOGIN_HEADERS}" "strict-transport-security")"
XFO="$(header_value "${LOGIN_HEADERS}" "x-frame-options")"
CACHE_CONTROL="$(header_value "${LOGIN_HEADERS}" "cache-control")"
PRAGMA="$(header_value "${LOGIN_HEADERS}" "pragma")"
EXPIRES="$(header_value "${LOGIN_HEADERS}" "expires")"
REFRESH="$(header_value "${LOGIN_HEADERS}" "refresh")"
LOGIN_ACAO="$(header_value "${LOGIN_HEADERS}" "access-control-allow-origin")"
LOGIN_ACAC="$(header_value "${LOGIN_HEADERS}" "access-control-allow-credentials")"
ACAO="$(header_value "${CORS_HEADERS}" "access-control-allow-origin")"
ACAC="$(header_value "${CORS_HEADERS}" "access-control-allow-credentials")"
VARY="$(header_value "${LOGIN_HEADERS}" "vary")"
CORS_VARY="$(header_value "${CORS_HEADERS}" "vary")"
HSTS_MAX_AGE="$(hsts_max_age "${HSTS}")"
TLS12_CIPHER="$(openssl_cipher "${OPENSSL_TLS12}" || true)"
TLS13_CIPHER="$(openssl_cipher "${OPENSSL_TLS13}" || true)"
NULL_CIPHER="$(openssl_cipher "${OPENSSL_NULL}" || true)"
BASE_FINAL_STATUS="$(final_status_code "${BASE_REDIRECTS}")"
LOGIN_REDIRECT_FINAL_STATUS="$(final_status_code "${LOGIN_REDIRECTS}")"

tracked_headers=(
  content-security-policy
  x-content-type-options
  referrer-policy
  permissions-policy
  strict-transport-security
  x-frame-options
  cache-control
  refresh
  access-control-allow-origin
  access-control-allow-credentials
  vary
)

CSP_WEAKNESSES=()
CSP_NOTES=()
if [[ -z "${CSP}" ]]; then
  CSP_NOTES+=("Content-Security-Policy header missing on final login response")
else
  SCRIPT_SRC="$(csp_directive "${CSP}" "script-src")"
  STYLE_SRC="$(csp_directive "${CSP}" "style-src")"
  FORM_ACTION="$(csp_directive "${CSP}" "form-action")"
  BASE_URI="$(csp_directive "${CSP}" "base-uri")"
  OBJECT_SRC="$(csp_directive "${CSP}" "object-src")"
  FRAME_ANCESTORS="$(csp_directive "${CSP}" "frame-ancestors")"
  if [[ " ${SCRIPT_SRC} " == *" 'unsafe-inline' "* ]]; then CSP_WEAKNESSES+=("script-src includes 'unsafe-inline'"); fi
  if [[ " ${SCRIPT_SRC} " == *" 'unsafe-eval' "* ]]; then CSP_WEAKNESSES+=("script-src includes 'unsafe-eval'"); fi
  if [[ " ${STYLE_SRC} " == *" 'unsafe-inline' "* ]]; then CSP_NOTES+=("style-src includes 'unsafe-inline'"); fi
  if [[ -z "${FORM_ACTION}" ]]; then CSP_WEAKNESSES+=("form-action directive is missing"); fi
  if [[ -z "${BASE_URI}" ]]; then CSP_NOTES+=("base-uri directive is missing"); fi
  if [[ -z "${OBJECT_SRC}" ]]; then CSP_NOTES+=("object-src directive is missing"); fi
  if [[ "${CSP}" == *"https://*"* || "${CSP}" == *"*."* ]]; then CSP_NOTES+=("broad wildcard source observed"); fi
  if [[ -n "${FRAME_ANCESTORS}" && ( " ${FRAME_ANCESTORS} " == *" * "* || "${FRAME_ANCESTORS}" == *"https://*"* ) ]]; then CSP_NOTES+=("broad frame-ancestors directive observed") ; fi
fi
if [[ "${#CSP_WEAKNESSES[@]}" -gt 0 ]]; then
  add_finding "Permissive Content-Security-Policy" "medium" "confirmed" "csp" "${LOGIN_URL}" \
    "$(append_joined '; ' "${CSP_WEAKNESSES[@]}" "${CSP_NOTES[@]}")" \
    "Phase 7 directly inspected the final login response CSP and grouped directly observed CSP weaknesses into one validation conclusion." \
    "Remove unsafe-eval; replace unsafe-inline with nonces/hashes where practical; add form-action 'self'; add base-uri 'self'; add object-src 'none'."
elif [[ -z "${CSP}" ]]; then
  add_finding "Permissive Content-Security-Policy" "medium" "needs_review" "csp" "${LOGIN_URL}" \
    "Content-Security-Policy header missing on final login response." \
    "No CSP was available for directive-level validation on the final login response." \
    "Add a restrictive Content-Security-Policy; remove unsafe-eval; replace unsafe-inline with nonces/hashes where practical; add form-action 'self'; add base-uri 'self'; add object-src 'none'."
fi

MISSING_HEADERS=()
[[ -z "${XCTO}" ]] && MISSING_HEADERS+=("X-Content-Type-Options")
[[ -z "${REFPOL}" ]] && MISSING_HEADERS+=("Referrer-Policy")
[[ -z "${PERMPOL}" ]] && MISSING_HEADERS+=("Permissions-Policy")
if [[ "${#MISSING_HEADERS[@]}" -gt 0 ]]; then
  add_finding "Missing recommended browser security headers" "low" "confirmed" "headers" "${LOGIN_URL}" \
    "Missing: $(append_joined ', ' "${MISSING_HEADERS[@]}")." \
    "The final login response is missing one or more recommended browser security headers." \
    "Set X-Content-Type-Options: nosniff; set Referrer-Policy: strict-origin-when-cross-origin; configure a restrictive Permissions-Policy baseline."
fi

if [[ -z "${HSTS}" ]]; then
  add_finding "HSTS header missing" "medium" "confirmed" "headers" "${LOGIN_URL}" \
    "Strict-Transport-Security was not present on the final login response." \
    "The final login response did not include HSTS, so browsers are not instructed to require HTTPS for this host after first contact." \
    "Set Strict-Transport-Security with max-age of at least 31536000 after confirming HTTPS readiness; consider includeSubDomains and preload where appropriate."
elif [[ -n "${HSTS_MAX_AGE}" && "${HSTS_MAX_AGE}" -lt 31536000 ]]; then
  add_finding "HSTS max-age below one-year hardening baseline" "low" "confirmed" "headers" "${LOGIN_URL}" \
    "Strict-Transport-Security max-age=${HSTS_MAX_AGE}, below 31536000." \
    "HSTS is present, but its max-age is below the one-year hardening baseline used by Phase 7." \
    "Increase Strict-Transport-Security max-age to at least 31536000 after confirming HTTPS readiness; consider includeSubDomains and preload where appropriate."
else
  add_finding "HSTS one-year hardening baseline met" "informational" "observed" "headers" "${LOGIN_URL}" \
    "Strict-Transport-Security present with max-age=${HSTS_MAX_AGE:-unparsed}." \
    "The final login response included HSTS and did not directly show a max-age below the Phase 7 one-year baseline." \
    "Continue maintaining HSTS; consider includeSubDomains and preload only if operationally appropriate."
fi

ACAO_LOWER="$(printf '%s' "${ACAO}" | tr '[:upper:]' '[:lower:]')"
ACAC_LOWER="$(printf '%s' "${ACAC}" | tr '[:upper:]' '[:lower:]')"
CORS_REFLECTS="false"
CORS_WILDCARD="false"
[[ "${ACAO_LOWER}" == "https://evil.example.com" ]] && CORS_REFLECTS="true"
[[ "${ACAO}" == "*" ]] && CORS_WILDCARD="true"
if [[ "${CORS_REFLECTS}" == "true" ]]; then
  cors_severity="medium"
  cors_evidence="Access-Control-Allow-Origin reflected https://evil.example.com"
  if [[ "${ACAC_LOWER}" == "true" ]]; then
    cors_severity="high"
    cors_evidence+=" and Access-Control-Allow-Credentials was true"
  fi
  add_finding "CORS arbitrary origin reflection" "${cors_severity}" "confirmed" "cors" "${LOGIN_URL}" \
    "${cors_evidence}." \
    "A direct login request with Origin: https://evil.example.com caused the response to reflect that arbitrary origin." \
    "Replace origin reflection with an explicit allowlist; do not combine arbitrary origins or wildcard ACAO with credentials."
else
  cors_evidence="ACAO=${ACAO:-missing}; ACAC=${ACAC:-missing}"
  if [[ "${CORS_WILDCARD}" == "true" && "${ACAC_LOWER}" == "true" ]]; then
    add_finding "CORS wildcard with credentials" "high" "confirmed" "cors" "${LOGIN_URL}" \
      "Access-Control-Allow-Origin was * and Access-Control-Allow-Credentials was true." \
      "A direct CORS validation request observed a risky wildcard plus credentials combination." \
      "Use an explicit origin allowlist and do not permit credentials for arbitrary origins."
  else
    add_finding "CORS arbitrary origin reflection" "informational" "not_observed" "cors" "${LOGIN_URL}" \
      "${cors_evidence}; https://evil.example.com was not reflected." \
      "A direct CORS validation request did not observe arbitrary origin reflection." \
      "Continue using an explicit origin allowlist and avoid credentials for untrusted origins."
  fi
fi

CACHE_LOWER="$(printf '%s;%s;%s' "${CACHE_CONTROL}" "${PRAGMA}" "${EXPIRES}" | tr '[:upper:]' '[:lower:]')"
if [[ "${CACHE_LOWER}" == *"no-store"* || "${CACHE_LOWER}" == *"private"* || "${CACHE_LOWER}" == *"no-cache"* || "${CACHE_LOWER}" == *"max-age=0"* ]]; then
  add_finding "Login cache protection" "informational" "not_observed" "cache" "${LOGIN_URL}" \
    "Cache protection observed: Cache-Control=${CACHE_CONTROL:-missing}; Pragma=${PRAGMA:-missing}; Expires=${EXPIRES:-missing}." \
    "The final login response includes no-store or equivalent sensitive-page cache protection, so cache risk was not observed." \
    "Continue sending no-store or equivalent cache controls on sensitive authentication pages."
else
  add_finding "Login cache protection missing" "medium" "confirmed" "cache" "${LOGIN_URL}" \
    "Cache-Control=${CACHE_CONTROL:-missing}; Pragma=${PRAGMA:-missing}; Expires=${EXPIRES:-missing}." \
    "The final login response did not include no-store, private, no-cache, or equivalent sensitive-page cache protection." \
    "Set Cache-Control: no-store on sensitive login and authenticated pages; include Pragma: no-cache and Expires: 0 where legacy compatibility is needed."
fi

if [[ "${NULL_CIPHER}" =~ (NULL|aNULL|eNULL|ADH|AECDH) ]] && [[ "${NULL_CIPHER}" != "(NONE)" ]] && ! grep -Eiq 'Cipher is \(NONE\)|no cipher match|handshake failure|alert handshake failure|no peer certificate' "${OPENSSL_NULL}"; then
  add_finding "NULL/anonymous cipher support" "high" "confirmed" "tls" "${TARGET_BASE_URL}" \
    "Restricted OpenSSL TLS 1.2 validation negotiated ${NULL_CIPHER}." \
    "Phase 7 directly negotiated a NULL or anonymous cipher using a restricted OpenSSL cipher list." \
    "Disable NULL, eNULL, aNULL, ADH, and anonymous cipher suites at the TLS termination layer."
else
  null_evidence="Restricted OpenSSL TLS 1.2 NULL/aNULL/eNULL check did not negotiate a NULL or anonymous cipher; cipher=${NULL_CIPHER:-not negotiated}; exit=${null_code}."
  if grep -Eiq 'Cipher is \(NONE\)' "${OPENSSL_NULL}"; then
    null_evidence="Restricted OpenSSL TLS 1.2 NULL/aNULL/eNULL check returned Cipher is (NONE); NULL/anonymous support is not confirmed."
  fi
  add_finding "NULL/anonymous cipher support" "informational" "not_confirmed" "tls" "${TARGET_BASE_URL}" \
    "${null_evidence}" \
    "The direct restricted OpenSSL validation did not negotiate a real NULL or anonymous cipher." \
    "Keep NULL, eNULL, aNULL, ADH, and anonymous cipher suites disabled."
fi

TLS12_OK="false"
TLS13_OK="false"
[[ "${tls12_code}" -eq 0 && -n "${TLS12_CIPHER}" && "${TLS12_CIPHER}" != "(NONE)" ]] && TLS12_OK="true"
[[ "${tls13_code}" -eq 0 && -n "${TLS13_CIPHER}" && "${TLS13_CIPHER}" != "(NONE)" ]] && TLS13_OK="true"
if [[ "${TLS12_OK}" == "true" && "${TLS13_OK}" == "true" ]]; then
  add_finding "TLS modern protocol support" "informational" "observed" "tls" "${TARGET_BASE_URL}" \
    "TLS 1.2 negotiated ${TLS12_CIPHER}; TLS 1.3 negotiated ${TLS13_CIPHER}." \
    "Direct OpenSSL validation successfully negotiated both TLS 1.2 and TLS 1.3." \
    "Continue supporting modern TLS versions and strong cipher suites."
elif [[ "${TLS12_OK}" == "true" && "${TLS13_OK}" != "true" ]]; then
  add_finding "TLS 1.3 not negotiated" "low" "confirmed" "tls" "${TARGET_BASE_URL}" \
    "TLS 1.2 negotiated ${TLS12_CIPHER}; TLS 1.3 did not negotiate successfully; TLS 1.3 exit=${tls13_code}, cipher=${TLS13_CIPHER:-not negotiated}." \
    "Direct OpenSSL validation could not negotiate TLS 1.3." \
    "Enable TLS 1.3 where supported by the TLS termination layer."
else
  add_finding "TLS modern protocol support needs review" "medium" "needs_review" "tls" "${TARGET_BASE_URL}" \
    "TLS 1.2 exit=${tls12_code}, cipher=${TLS12_CIPHER:-not negotiated}; TLS 1.3 exit=${tls13_code}, cipher=${TLS13_CIPHER:-not negotiated}." \
    "Direct OpenSSL validation did not establish the expected modern TLS baseline." \
    "Review TLS listener availability, protocol configuration, certificates, and network path; enable TLS 1.2+ with strong cipher suites."
fi

add_finding "Redirect behavior" "informational" "observed" "redirect" "${TARGET_BASE_URL}" \
  "Base final status=${BASE_FINAL_STATUS:-unknown}; login redirect final status=${LOGIN_REDIRECT_FINAL_STATUS:-unknown}; login capture final status=${LOGIN_STATUS:-unknown}; Refresh header=${REFRESH:-missing}." \
  "Phase 7 captured base and login redirect chains for context. Missing headers on redirect-only base responses are not promoted to confirmed report findings." \
  "Review redirect chains for correctness; keep security-header findings focused on final login responses unless redirect responses carry sensitive content."

python3 - "${FINDINGS_TSV}" "${FINDINGS_FILE}" <<'PY'
import csv
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
dest = Path(sys.argv[2])
fields = ["id", "title", "severity", "status", "category", "url", "evidence", "description", "recommendation"]
items = []
with source.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.reader(handle, delimiter="\x1f")
    for row in reader:
        if not row:
            continue
        item = dict(zip(fields, row))
        item["source"] = "phase-7-validation"
        ordered = {
            "id": item["id"],
            "title": item["title"],
            "severity": item["severity"],
            "status": item["status"],
            "source": item["source"],
            "category": item["category"],
            "url": item["url"],
            "evidence": item["evidence"],
            "description": item["description"],
            "recommendation": item["recommendation"],
        }
        items.append(ordered)
dest.write_text(json.dumps(items, indent=2) + "\n", encoding="utf-8")
PY
rm -f "${FINDINGS_TSV}"

count_by() {
  local key="$1"
  python3 - "${FINDINGS_FILE}" "${key}" <<'PY'
import json
import sys
from collections import Counter
items = json.load(open(sys.argv[1], encoding="utf-8"))
counts = Counter(item[sys.argv[2]] for item in items)
for name in sorted(counts):
    print(f"{name}: {counts[name]}")
PY
}

section_findings() {
  local heading="$1"
  local statuses="$2"
  python3 - "${FINDINGS_FILE}" "${statuses}" <<'PY'
import json
import sys
items = json.load(open(sys.argv[1], encoding="utf-8"))
statuses = set(sys.argv[2].split(","))
matched = [item for item in items if item["status"] in statuses]
if not matched:
    print("- None")
for item in matched:
    print(f"- **{item['id']} {item['title']}** ({item['severity']}, {item['status']}): {item['evidence']}")
PY
}

{
  printf '# Phase 7 Final Validation Summary\n\n'
  printf '## Target URLs\n\n'
  printf -- '- Target base URL: %s\n' "${TARGET_BASE_URL}"
  printf -- '- Login URL: %s\n' "${LOGIN_URL}"
  printf -- '- Target host: %s\n\n' "${TARGET_HOST}"
  printf '## Run Metadata\n\n'
  printf -- '- Run ID: %s\n' "${PHASE_RUN_ID}"
  printf -- '- Started UTC: %s\n' "${STARTED_UTC}"
  printf -- '- Profile: %s\n' "${PROFILE}"
  printf -- '- curl binary: %s\n' "${CURL_BIN}"
  printf -- '- openssl binary: %s\n\n' "${OPENSSL_BIN}"
  printf '## Checks Performed\n\n'
  printf -- '- Captured final login headers and body with direct curl request.\n'
  printf -- '- Extracted report-relevant headers: %s.\n' "$(append_joined ', ' "${tracked_headers[@]}")"
  printf -- '- Validated CSP directives and broad source patterns on the final login response.\n'
  printf -- '- Validated missing browser security headers on the final login response.\n'
  printf -- '- Validated HSTS presence and max-age hardening baseline.\n'
  printf -- '- Validated sensitive-page cache controls.\n'
  printf -- '- Sent a single direct CORS request with Origin: https://evil.example.com.\n'
  printf -- '- Captured base and login redirect chains.\n'
  printf -- '- Ran direct OpenSSL TLS 1.2, TLS 1.3, and restricted NULL/aNULL/eNULL TLS 1.2 checks.\n\n'
  printf '## Header Extraction\n\n'
  for header_name in "${tracked_headers[@]}"; do
    case "${header_name}" in
      content-security-policy) value="${CSP}" ;;
      x-content-type-options) value="${XCTO}" ;;
      referrer-policy) value="${REFPOL}" ;;
      permissions-policy) value="${PERMPOL}" ;;
      strict-transport-security) value="${HSTS}" ;;
      x-frame-options) value="${XFO}" ;;
      cache-control) value="${CACHE_CONTROL}" ;;
      refresh) value="${REFRESH}" ;;
      access-control-allow-origin) value="${LOGIN_ACAO}" ;;
      access-control-allow-credentials) value="${LOGIN_ACAC}" ;;
      vary) value="login=${VARY:-missing}; cors=${CORS_VARY:-missing}" ;;
      *) value="" ;;
    esac
    printf -- '- %s: %s\n' "${header_name}" "${value:-MISSING}"
  done
  printf '\n## CORS Probe Header Extraction\n\n'
  printf -- '- access-control-allow-origin: %s\n' "${ACAO:-MISSING}"
  printf -- '- access-control-allow-credentials: %s\n' "${ACAC:-MISSING}"
  printf -- '- vary: %s\n' "${CORS_VARY:-MISSING}"
  printf '\n## Confirmed Findings\n\n'
  section_findings "Confirmed Findings" "confirmed"
  printf '\n## Not Confirmed Findings\n\n'
  section_findings "Not Confirmed Findings" "not_confirmed,not_observed,needs_review"
  printf '\n## Informational Observations\n\n'
  section_findings "Informational Observations" "informational,observed"
  printf '\n## Direct Evidence Files\n\n'
  for evidence_file in \
    "${LOGIN_HEADERS}" \
    "${LOGIN_BODY}" \
    "${CORS_HEADERS}" \
    "${BASE_REDIRECTS}" \
    "${LOGIN_REDIRECTS}" \
    "${OPENSSL_TLS12}" \
    "${OPENSSL_TLS13}" \
    "${OPENSSL_NULL}" \
    "${CONSOLE_LOG}" \
    "${FINDINGS_FILE}"; do
    printf -- '- %s\n' "${evidence_file##*/}"
  done
  printf '\n## Limitations\n\n'
  printf -- '- Phase 7 is not a crawler, fuzzer, brute-force tool, authenticated test, or active exploitation phase.\n'
  printf -- '- Findings are confirmed only when this phase directly observed the condition with bounded requests/checks.\n'
  printf -- '- Scanner-only observations from earlier phases are de-duplicated into validation-level conclusions here and are not automatically confirmed.\n'
  printf -- '- Redirect-only base response header gaps are retained as context and are not promoted to confirmed missing-header findings.\n'
  printf -- '- Authenticated testing remains placeholder-only until explicit safe handling exists.\n'
} > "${SUMMARY_FILE}"

copy_latest "${CONSOLE_LOG}" "${OUT}/validation-console-latest.txt"

VALIDATION_MESSAGE="Phase 7 final validation completed."
log_console "Final status: success"
log_console "Summary path: ${SUMMARY_FILE}"
log_console "Findings path: ${FINDINGS_FILE}"
log_console "Evidence directory: ${OUT}"
log_console "Finding count by severity:"
count_by severity | tee -a "${CONSOLE_LOG}"
log_console "Finding count by status:"
count_by status | tee -a "${CONSOLE_LOG}"
copy_latest "${CONSOLE_LOG}" "${OUT}/validation-console-latest.txt"
