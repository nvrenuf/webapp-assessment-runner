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

write_headers_findings() {
  local findings_file="${OUT}/headers-findings.json"
  local python_bin="${PYTHON_BIN:-python3}"
  "${python_bin}" - "${OUT}" "${TARGET_BASE_URL}" "${LOGIN_URL}" > "${findings_file}" <<'PY'
import json
import re
import sys
from pathlib import Path

out = Path(sys.argv[1])
target_base_url = sys.argv[2]
login_url = sys.argv[3]

findings = []


def read_text(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def header_values(path):
    values = {}
    for line in read_text(path).splitlines():
        if ":" not in line:
            continue
        name, value = line.split(":", 1)
        name = name.strip().lower()
        value = value.strip()
        if not name:
            continue
        values.setdefault(name, []).append(value)
    return {key: "; ".join(parts) for key, parts in values.items()}


def first_status(path):
    for line in read_text(path).splitlines():
        if line.startswith("HTTP/"):
            return line.strip()
    return ""


def status_code(status_line):
    match = re.search(r"\s([0-9]{3})\s", f"{status_line} ")
    return int(match.group(1)) if match else None


def csp_checks(label):
    checks = {}
    for line in read_text(out / "csp-analysis.txt").splitlines():
        parts = line.split("\t", 3)
        if len(parts) == 4 and parts[0] == label:
            checks[parts[1]] = {"status": parts[2], "details": parts[3]}
    return checks


def next_id():
    return f"HEADERS-{len(findings) + 1:03d}"


def add(title, severity, status, category, url, evidence, description, recommendation):
    findings.append(
        {
            "id": next_id(),
            "title": title,
            "severity": severity,
            "status": status,
            "source": "phase-2-headers",
            "category": category,
            "url": url,
            "evidence": evidence,
            "description": description,
            "recommendation": recommendation,
        }
    )


login_headers = header_values(out / "login-headers-latest.txt")
base_headers = header_values(out / "base-headers-latest.txt")
login_cors_headers = header_values(out / "login-cors-headers-latest.txt")
base_redirect_status = first_status(out / "base-redirects-latest.txt")
base_redirect_code = status_code(base_redirect_status)
login_csp = csp_checks("login")

csp_finding_map = {
    "script-src-unsafe-inline": (
        "CSP permits unsafe inline JavaScript on login",
        "medium",
        "confirmed",
        "script-src includes 'unsafe-inline'",
        "Inline JavaScript weakens Content-Security-Policy protections and can increase XSS impact.",
        "Move inline scripts to external files with nonces or hashes and remove 'unsafe-inline' from script-src.",
    ),
    "script-src-unsafe-eval": (
        "CSP permits unsafe JavaScript evaluation on login",
        "medium",
        "confirmed",
        "script-src includes 'unsafe-eval'",
        "Use of unsafe-eval allows dynamic JavaScript execution patterns that weaken CSP protection.",
        "Remove 'unsafe-eval' from script-src and refactor code that depends on eval-like behavior.",
    ),
    "style-src-unsafe-inline": (
        "CSP permits unsafe inline styles on login",
        "low",
        "confirmed",
        "style-src includes 'unsafe-inline'",
        "Inline style allowances weaken CSP style restrictions.",
        "Replace inline styles with stylesheet rules or use CSP hashes/nonces where required.",
    ),
    "missing-form-action": (
        "CSP is missing form-action on login",
        "medium",
        "confirmed",
        "form-action directive is not defined",
        "Without form-action, CSP does not restrict where login forms may submit data.",
        "Add `form-action 'self';`.",
    ),
    "missing-base-uri": (
        "CSP is missing base-uri on login",
        "low",
        "confirmed",
        "base-uri directive is not defined",
        "Without base-uri, injected base tags may alter relative URL resolution.",
        "Add `base-uri 'self';`.",
    ),
    "missing-object-src": (
        "CSP is missing object-src on login",
        "low",
        "confirmed",
        "object-src directive is not defined",
        "Without object-src, legacy plugin/object embedding is not explicitly restricted.",
        "Add `object-src 'none';`.",
    ),
}

for check, (title, severity, status, expected_detail, description, recommendation) in csp_finding_map.items():
    item = login_csp.get(check)
    if item and item["details"] == expected_detail:
        add(title, severity, status, "csp", login_url, item["details"], description, recommendation)

for check, title, evidence_prefix, description, recommendation in (
    (
        "broad-wildcard-sources",
        "CSP contains broad wildcard sources on login",
        "Broad wildcard source observed",
        "Wildcard CSP sources can allow content from overly broad third-party locations.",
        "Replace wildcard sources with the smallest explicit source allowlist that supports the application.",
    ),
    (
        "broad-frame-ancestors",
        "CSP frame-ancestors may be overly broad on login",
        "Broad frame-ancestors observed",
        "Broad frame-ancestors values can weaken clickjacking protections.",
        "Restrict frame-ancestors to 'self' or a small explicit allowlist.",
    ),
):
    item = login_csp.get(check)
    if item and item["status"] == "needs review":
        add(title, "low", "needs_review", "csp", login_url, f"{evidence_prefix}: {item['details']}", description, recommendation)

required_headers = {
    "x-content-type-options": (
        "Missing X-Content-Type-Options on login",
        "`X-Content-Type-Options: nosniff`",
        "The login response does not explicitly prevent MIME type sniffing.",
    ),
    "referrer-policy": (
        "Missing Referrer-Policy on login",
        "`Referrer-Policy: strict-origin-when-cross-origin`",
        "The login response does not define how much referrer information browsers may send.",
    ),
    "permissions-policy": (
        "Missing Permissions-Policy on login",
        "Restrictive baseline such as `Permissions-Policy: geolocation=(), microphone=(), camera=()`",
        "The login response does not restrict browser features through Permissions-Policy.",
    ),
}

for header, (title, recommendation, description) in required_headers.items():
    if not login_headers.get(header):
        add(title, "low", "confirmed", "headers", login_url, f"{header}: MISSING", description, recommendation)

hsts_value = login_headers.get("strict-transport-security", "")
max_age_match = re.search(r"max-age\s*=\s*([0-9]+)", hsts_value, flags=re.IGNORECASE)
if max_age_match and int(max_age_match.group(1)) < 31536000:
    add(
        "HSTS max-age is below one year on login",
        "low",
        "confirmed",
        "headers",
        login_url,
        f"Strict-Transport-Security: {hsts_value}",
        "The login response enables HSTS with a max-age shorter than the common one-year baseline.",
        "Set Strict-Transport-Security max-age to at least 31536000 after validating HTTPS coverage.",
    )

cache_value = login_headers.get("cache-control", "")
if "no-store" not in cache_value.lower():
    add(
        "Login response lacks no-store cache protection",
        "medium",
        "confirmed",
        "cache",
        login_url,
        f"Cache-Control: {cache_value or 'MISSING'}",
        "Login responses can contain sensitive information and should not be stored by browsers or intermediaries.",
        "Set `Cache-Control: no-store` on login and other sensitive authenticated responses.",
    )

acao = login_cors_headers.get("access-control-allow-origin", "")
acac = login_cors_headers.get("access-control-allow-credentials", "")
origin_reflected = acao == "https://evil.example"
wildcard_origin = acao == "*"
credentials_allowed = acac.lower() == "true"

if origin_reflected:
    add(
        "CORS reflects arbitrary Origin on login",
        "medium",
        "confirmed",
        "cors",
        login_url,
        f"Access-Control-Allow-Origin: {acao}",
        "The login response reflects an arbitrary Origin value in Access-Control-Allow-Origin.",
        "Return Access-Control-Allow-Origin only for trusted origins from a strict allowlist.",
    )
else:
    add(
        "CORS arbitrary origin reflection not observed on login",
        "informational",
        "not_observed",
        "cors",
        login_url,
        f"Access-Control-Allow-Origin: {acao or 'MISSING'}",
        "The Phase 2 arbitrary-origin probe did not observe reflection of https://evil.example.",
        "Continue to validate CORS behavior for authenticated API endpoints when authenticated testing is enabled.",
    )

if (origin_reflected or wildcard_origin) and credentials_allowed:
    add(
        "CORS permits arbitrary origin with credentials on login",
        "high",
        "confirmed",
        "cors",
        login_url,
        f"Access-Control-Allow-Origin: {acao}; Access-Control-Allow-Credentials: {acac}",
        "The login response combines broad origin allowance with credentialed CORS behavior.",
        "Do not combine credentialed CORS with reflected or wildcard origins; use a strict trusted-origin allowlist.",
    )

if base_redirect_code in {301, 302, 303, 307, 308}:
    location = base_headers.get("location", "")
    add(
        "Base URL returns redirect response",
        "informational",
        "observed",
        "redirect",
        target_base_url,
        f"{base_redirect_status}; Location: {location or 'see redirect evidence'}",
        "The base URL returned a redirect during header capture.",
        "Review redirect targets for expected routing and HTTPS consistency.",
    )

print(json.dumps(findings, indent=2))
PY
}

write_headers_findings

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
- structured findings: headers-findings.json
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
