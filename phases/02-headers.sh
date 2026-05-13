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
    -name '*-cors-headers-[0-9]*T[0-9]*Z.txt' -o \
    -name 'phase-2-headers-console-[0-9]*T[0-9]*Z.txt' -o \
    -name '*-headers-latest.txt' -o \
    -name '*-body-latest.html' -o \
    -name '*-redirects-latest.txt' -o \
    -name '*-cors-headers-latest.txt' \
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
  local cors_headers_file="${OUT}/${label}-cors-headers-${PHASE_RUN_ID}.txt"

  log_console "Capturing ${label}: ${url}"

  set +e
  "${CURL_BIN}" -k -s -D "${headers_file}" -o "${body_file}" --max-time 30 "${url}" >> "${CONSOLE_LOG}" 2>&1
  local capture_code=$?
  "${CURL_BIN}" -k -s -IL --max-time 30 "${url}" > "${redirects_file}" 2>> "${CONSOLE_LOG}"
  local redirects_code=$?
  "${CURL_BIN}" -k -s -H "Origin: https://evil.example" -D "${cors_headers_file}" -o /dev/null --max-time 30 "${url}" >> "${CONSOLE_LOG}" 2>&1
  local cors_code=$?
  set -e

  copy_latest "${headers_file}" "${OUT}/${label}-headers-latest.txt"
  copy_latest "${body_file}" "${OUT}/${label}-body-latest.html"
  copy_latest "${redirects_file}" "${OUT}/${label}-redirects-latest.txt"
  copy_latest "${cors_headers_file}" "${OUT}/${label}-cors-headers-latest.txt"

  if [[ "${capture_code}" -ne 0 ]]; then
    fail_headers "curl header/body capture failed for ${label} (${url})"
  fi
  if [[ "${redirects_code}" -ne 0 ]]; then
    fail_headers "curl redirect capture failed for ${label} (${url})"
  fi
  if [[ "${cors_code}" -ne 0 ]]; then
    fail_headers "curl CORS header capture failed for ${label} (${url})"
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

write_csp_analysis() {
  local txt_file="${OUT}/csp-analysis.txt"
  local md_file="${OUT}/csp-analysis.md"
  : > "${txt_file}"
  : > "${md_file}"

  printf '# CSP Analysis\n\n' > "${md_file}"

  for label in base login; do
    local header_file="${OUT}/${label}-headers-latest.txt"
    local csp_value
    csp_value="$(header_value "${header_file}" "content-security-policy")"

    {
      printf '## %s\n\n' "${label}"
      if [[ -z "${csp_value}" ]]; then
        printf -- '- CSP present: no\n'
        printf -- '- Raw CSP: MISSING\n\n'
        printf '### Directive Summary\n\n'
        printf 'No Content-Security-Policy header was captured.\n\n'
        printf '### Weakness Observations\n\n'
        printf -- '- CSP missing: missing\n\n'
      else
        printf -- '- CSP present: yes\n'
        printf -- '- Raw CSP:\n\n'
        printf '```text\n%s\n```\n\n' "${csp_value}"
        printf '### Directive Summary\n\n'
        printf '%s\n' "${csp_value}" | awk '
          BEGIN { FS = ";" }
          {
            for (i = 1; i <= NF; i++) {
              directive = $i
              gsub(/^[ \t]+|[ \t]+$/, "", directive)
              if (directive != "") {
                name = directive
                sub(/[ \t].*$/, "", name)
                lower = tolower(name)
                value = directive
                sub(/^[^ \t]+[ \t]*/, "", value)
                if (value == directive) value = ""
                printf "- %s: %s\n", lower, value
              }
            }
          }
        '
        printf '\n### Weakness Observations\n\n'
      fi
    } >> "${md_file}"

    printf '%s\n' "${csp_value}" | awk -v label="${label}" -v txt="${txt_file}" -v md="${md_file}" '
      function trim(value) {
        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", value)
        return value
      }
      function emit(check, status, details) {
        printf "%s\t%s\t%s\t%s\n", label, check, status, details >> txt
        printf "- %s: %s - %s\n", check, status, details >> md
      }
      BEGIN {
        raw = ""
      }
      {
        raw = raw $0
      }
      END {
        if (raw == "") {
          emit("csp-present", "missing", "Content-Security-Policy header is not present")
          emit("default-src", "missing", "default-src directive is not defined")
          emit("script-src-unsafe-inline", "not observed", "script-src directive is not defined")
          emit("script-src-unsafe-eval", "not observed", "script-src directive is not defined")
          emit("style-src-unsafe-inline", "not observed", "style-src directive is not defined")
          emit("missing-form-action", "missing", "form-action directive is not defined")
          emit("missing-base-uri", "missing", "base-uri directive is not defined")
          emit("missing-object-src", "missing", "object-src directive is not defined")
          emit("broad-wildcard-sources", "not observed", "CSP is missing")
          emit("broad-frame-ancestors", "missing", "frame-ancestors directive is not defined")
          exit
        }

        emit("csp-present", "observed", "Content-Security-Policy header is present")

        split(raw, parts, ";")
        for (i in parts) {
          directive = trim(parts[i])
          if (directive == "") continue
          name = directive
          sub(/[ \t].*$/, "", name)
          name = tolower(name)
          value = directive
          sub(/^[^ \t]+[ \t]*/, "", value)
          if (value == directive) value = ""
          directives[name] = value
        }

        if ("default-src" in directives) {
          emit("default-src", "observed", "default-src is defined")
        } else {
          emit("default-src", "missing", "default-src directive is not defined")
        }

        script = ("script-src" in directives) ? directives["script-src"] : ""
        style = ("style-src" in directives) ? directives["style-src"] : ""
        if (script ~ /'\''unsafe-inline'\''/) emit("script-src-unsafe-inline", "observed", "script-src includes '\''unsafe-inline'\''")
        else emit("script-src-unsafe-inline", "not observed", "script-src does not include '\''unsafe-inline'\''")
        if (script ~ /'\''unsafe-eval'\''/) emit("script-src-unsafe-eval", "observed", "script-src includes '\''unsafe-eval'\''")
        else emit("script-src-unsafe-eval", "not observed", "script-src does not include '\''unsafe-eval'\''")
        if (style ~ /'\''unsafe-inline'\''/) emit("style-src-unsafe-inline", "observed", "style-src includes '\''unsafe-inline'\''")
        else emit("style-src-unsafe-inline", "not observed", "style-src does not include '\''unsafe-inline'\''")

        if ("form-action" in directives) emit("missing-form-action", "observed", "form-action directive is defined")
        else emit("missing-form-action", "missing", "form-action directive is not defined")
        if ("base-uri" in directives) emit("missing-base-uri", "observed", "base-uri directive is defined")
        else emit("missing-base-uri", "missing", "base-uri directive is not defined")
        if ("object-src" in directives) emit("missing-object-src", "observed", "object-src directive is defined")
        else emit("missing-object-src", "missing", "object-src directive is not defined")

        broad = 0
        broad_details = ""
        for (name in directives) {
          value = directives[name]
          if (value ~ /(^|[ \t])\*($|[ \t])/) {
            broad = 1
            broad_details = broad_details name " includes bare wildcard; "
          }
          if (value ~ /https:\/\/\*\./) {
            broad = 1
            broad_details = broad_details name " includes https://*. wildcard; "
          }
        }
        if (broad) emit("broad-wildcard-sources", "needs review", broad_details)
        else emit("broad-wildcard-sources", "not observed", "no bare * or https://*. source observed")

        if ("frame-ancestors" in directives) {
          fa = directives["frame-ancestors"]
          count = split(fa, fa_parts, /[ \t]+/)
          if (fa ~ /\*/ || fa ~ /https:\/\/\*\./) {
            emit("broad-frame-ancestors", "needs review", "frame-ancestors contains wildcard source")
          } else if (fa == "'\''self'\''" || count <= 3) {
            emit("broad-frame-ancestors", "not observed", "frame-ancestors appears restricted")
          } else {
            emit("broad-frame-ancestors", "needs review", "frame-ancestors has multiple allowed sources")
          }
        } else {
          emit("broad-frame-ancestors", "missing", "frame-ancestors directive is not defined")
        }
      }
    '
    printf '\n' >> "${md_file}"
  done
}

write_csp_analysis

write_cors_analysis() {
  local txt_file="${OUT}/cors-analysis.txt"
  local md_file="${OUT}/cors-analysis.md"
  : > "${txt_file}"
  : > "${md_file}"

  printf '# CORS Analysis\n\n' > "${md_file}"

  for label in base login; do
    local header_file="${OUT}/${label}-cors-headers-latest.txt"
    local acao acac acam acah vary
    acao="$(header_value "${header_file}" "access-control-allow-origin")"
    acac="$(header_value "${header_file}" "access-control-allow-credentials")"
    acam="$(header_value "${header_file}" "access-control-allow-methods")"
    acah="$(header_value "${header_file}" "access-control-allow-headers")"
    vary="$(header_value "${header_file}" "vary")"

    local arbitrary_status="not observed"
    local wildcard_status="not observed"
    local credentials_status="not observed"
    local risky_status="not observed"

    if [[ "${acao}" == "https://evil.example" ]]; then
      arbitrary_status="observed"
    fi
    if [[ "${acao}" == "*" ]]; then
      wildcard_status="observed"
    fi
    if [[ "${acac,,}" == "true" ]]; then
      credentials_status="observed"
    fi
    if [[ "${credentials_status}" == "observed" && ( "${arbitrary_status}" == "observed" || "${wildcard_status}" == "observed" ) ]]; then
      risky_status="observed"
    fi

    {
      printf '%s\tarbitrary-origin-reflection\t%s\tACAO=%s\n' "${label}" "${arbitrary_status}" "${acao:-MISSING}"
      printf '%s\twildcard-origin\t%s\tACAO=%s\n' "${label}" "${wildcard_status}" "${acao:-MISSING}"
      printf '%s\tcredentials-allowed\t%s\tACAC=%s\n' "${label}" "${credentials_status}" "${acac:-MISSING}"
      printf '%s\trisky-cors-combination\t%s\tACAO=%s; ACAC=%s\n' "${label}" "${risky_status}" "${acao:-MISSING}" "${acac:-MISSING}"
    } >> "${txt_file}"

    {
      printf '## %s\n\n' "${label}"
      printf '### Raw CORS Response Headers\n\n'
      printf '```text\n'
      if [[ -f "${header_file}" ]]; then
        cat "${header_file}"
      else
        printf 'MISSING\n'
      fi
      printf '\n```\n\n'
      printf -- '- access-control-allow-origin: %s\n' "${acao:-MISSING}"
      printf -- '- access-control-allow-credentials: %s\n' "${acac:-MISSING}"
      printf -- '- access-control-allow-methods: %s\n' "${acam:-MISSING}"
      printf -- '- access-control-allow-headers: %s\n' "${acah:-MISSING}"
      printf -- '- vary: %s\n' "${vary:-MISSING}"
      printf -- '- arbitrary-origin-reflection: %s\n' "${arbitrary_status}"
      printf -- '- wildcard-origin: %s\n' "${wildcard_status}"
      printf -- '- credentials-allowed: %s\n' "${credentials_status}"
      printf -- '- risky-cors-combination: %s\n\n' "${risky_status}"
    } >> "${md_file}"
  done
}

write_cors_analysis

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
- base CORS headers: base-cors-headers-latest.txt
- login CORS headers: login-cors-headers-latest.txt
- security header markdown summary: security-header-summary.md
- security header text summary: security-header-summary.txt
- CSP markdown analysis: csp-analysis.md
- CSP text analysis: csp-analysis.txt
- CORS markdown analysis: cors-analysis.md
- CORS text analysis: cors-analysis.txt
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
