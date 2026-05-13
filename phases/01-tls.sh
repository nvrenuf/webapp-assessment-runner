#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"
source "${REPO_ROOT}/lib/evidence.sh"
source "${REPO_ROOT}/lib/status.sh"

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

PHASE_NAME="phase-1-tls"
STARTED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
TLS_STATUS="failure"
TLS_MESSAGE="TLS validation did not complete."
STATUS_READY="false"

finish_status() {
  local exit_code="$1"
  if [[ "${STATUS_READY}" == "true" ]]; then
    local finished_utc
    finished_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ "${exit_code}" -eq 0 ]]; then
      TLS_STATUS="success"
    fi
    write_phase_status_file "${WORKSPACE}" "${PHASE_NAME}" "${TLS_STATUS}" "${STARTED_UTC}" "${finished_utc}" "${exit_code}" "${TLS_MESSAGE}"
  fi
}
trap 'exit_code=$?; finish_status "${exit_code}"' EXIT

fail_tls() {
  TLS_MESSAGE="$1"
  die "$1"
}

validate_workspace "${WORKSPACE}"
OUT="$(phase_evidence_dir "${WORKSPACE}" "${PHASE_NAME}")"
STATUS_READY="true"

load_env_file "${WORKSPACE}/config/target.env"
require_env_vars TARGET_BASE_URL TARGET_HOST PROFILE

if [[ -f "${WORKSPACE}/config/tool-paths.env" ]]; then
  load_env_file "${WORKSPACE}/config/tool-paths.env"
fi

PROFILE_FILE="${REPO_ROOT}/config/profiles/${PROFILE}.env"
if [[ -f "${PROFILE_FILE}" ]]; then
  load_env_file "${PROFILE_FILE}"
fi

WARNINGS=()
FINDINGS=()
TESTSSL_RAN="false"
TESTSSL_STATUS="not available"
NULL_VALIDATION_STATUS="not required"
TLS12_CIPHER=""
TLS13_CIPHER=""
CERT_SUBJECT=""
CERT_ISSUER=""
CERT_DATES=""
VERIFY_RETURN_CODE=""
TLS12_RESULT="not checked"
TLS13_RESULT="not checked"
LEGACY_TLS_STATUS="not observed"
NULL_CIPHER_CONFIRMED="false"
TLS_POSTURE="not assessed"

detect_bin() {
  local configured="$1"
  shift
  if [[ -n "${configured}" && -x "${configured}" ]]; then
    printf '%s\n' "${configured}"
    return 0
  fi
  first_existing_command "$@"
}

TESTSSL_BIN="$(detect_bin "${TESTSSL_BIN:-}" testssl testssl.sh || true)"
OPENSSL_BIN="$(detect_bin "${OPENSSL_BIN:-}" openssl || true)"

[[ -n "${OPENSSL_BIN}" ]] || fail_tls "required tool missing: openssl"

add_finding() {
  local title="$1"
  local severity="$2"
  local status="$3"
  local description="$4"
  FINDINGS+=("${title}|${severity}|${status}|${description}")
}

legacy_tls_offered() {
  awk '
    {
      line = tolower($0)
      if (line ~ /(tlsv? 1[.]0|tlsv?1[.]0|tls 1[.]0|tlsv? 1[.]1|tlsv?1[.]1|tls 1[.]1)/) {
        if (line ~ /(not offered|not available|not supported|not vulnerable)/) {
          next
        }
        if (line ~ /(offered|enabled|accepted|supported)/) {
          found = 1
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$@"
}

openssl_cipher() {
  local file="$1"
  {
    grep -E '^[[:space:]]*Cipher[[:space:]]*:' "${file}" | sed -E 's/^[[:space:]]*Cipher[[:space:]]*:[[:space:]]*//'
    grep -E 'Cipher is ' "${file}" | sed -E 's/^.*Cipher is //'
  } | tail -n 1
}

extract_cert_metadata() {
  local file="$1"
  CERT_SUBJECT="$(grep -E '^subject=' "${file}" | head -n 1 | sed 's/^subject=//' || true)"
  CERT_ISSUER="$(grep -E '^issuer=' "${file}" | head -n 1 | sed 's/^issuer=//' || true)"
  VERIFY_RETURN_CODE="$(grep -E 'Verify return code:' "${file}" | tail -n 1 | sed -E 's/^[[:space:]]*Verify return code:[[:space:]]*//' || true)"
  CERT_DATES="$("${OPENSSL_BIN}" x509 -noout -dates -in "${file}" 2>/dev/null | tr '\n' ';' || true)"
}

if [[ -n "${TESTSSL_BIN}" ]]; then
  set +e
  "${TESTSSL_BIN}" --fast --warnings batch --logfile "${OUT}/testssl-fast.log" "${TARGET_BASE_URL}" 2>&1 | tee "${OUT}/testssl-fast-console.txt"
  testssl_code=${PIPESTATUS[0]}
  set -e
  TESTSSL_RAN="true"
  TESTSSL_STATUS="completed with exit code ${testssl_code}"
  if [[ "${testssl_code}" -ne 0 ]]; then
    WARNINGS+=("testssl exited with code ${testssl_code}; review raw output")
  fi
else
  TESTSSL_STATUS="missing"
  WARNINGS+=("testssl not found; continuing with OpenSSL checks")
  printf 'testssl not found; OpenSSL checks only.\n' > "${OUT}/testssl-fast-console.txt"
fi

set +e
"${OPENSSL_BIN}" s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -tls1_2 </dev/null > "${OUT}/openssl-tls12.txt" 2>&1
tls12_code=$?
"${OPENSSL_BIN}" s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -tls1_3 </dev/null > "${OUT}/openssl-tls13.txt" 2>&1
tls13_code=$?
set -e

if [[ "${tls12_code}" -eq 0 ]]; then
  TLS12_RESULT="completed"
else
  TLS12_RESULT="failed with exit code ${tls12_code}"
  WARNINGS+=("OpenSSL TLS 1.2 validation failed; review openssl-tls12.txt")
fi
if [[ "${tls13_code}" -eq 0 ]]; then
  TLS13_RESULT="completed"
else
  TLS13_RESULT="failed with exit code ${tls13_code}"
  WARNINGS+=("OpenSSL TLS 1.3 validation failed or TLS 1.3 is unsupported; informational")
fi

TLS12_CIPHER="$(openssl_cipher "${OUT}/openssl-tls12.txt" || true)"
TLS13_CIPHER="$(openssl_cipher "${OUT}/openssl-tls13.txt" || true)"
extract_cert_metadata "${OUT}/openssl-tls12.txt"

if [[ "${TLS12_CIPHER}" =~ (GCM|CHACHA20|POLY1305) ]]; then
  add_finding "TLS 1.2 negotiated AEAD cipher" "informational" "observed" "TLS 1.2 negotiated ${TLS12_CIPHER}."
fi
if [[ "${TLS13_CIPHER}" =~ (GCM|CHACHA20|POLY1305) ]]; then
  add_finding "TLS 1.3 negotiated AEAD cipher" "informational" "observed" "TLS 1.3 negotiated ${TLS13_CIPHER}."
fi
if [[ "${VERIFY_RETURN_CODE}" != "" && ! "${VERIFY_RETURN_CODE}" =~ ^0[[:space:]]+\(ok\) ]]; then
  add_finding "Certificate verification issue" "medium" "unvalidated" "OpenSSL reported verify return code: ${VERIFY_RETURN_CODE}."
fi

TESTSSL_FILES=("${OUT}/testssl-fast-console.txt")
if [[ -f "${OUT}/testssl-fast.log" ]]; then
  TESTSSL_FILES+=("${OUT}/testssl-fast.log")
fi

if grep -Eiq 'NULL ciphers|Anonymous NULL|aNULL|eNULL' "${TESTSSL_FILES[@]}"; then
  set +e
  "${OPENSSL_BIN}" s_client -connect "${TARGET_HOST}:443" -servername "${TARGET_HOST}" -cipher 'NULL:eNULL:aNULL' -tls1_2 </dev/null > "${OUT}/openssl-null-anon.txt" 2>&1
  null_code=$?
  set -e
  NULL_VALIDATION_STATUS="ran with exit code ${null_code}"
  null_cipher="$(openssl_cipher "${OUT}/openssl-null-anon.txt" || true)"
  if [[ "${null_cipher}" =~ (NULL|aNULL|eNULL) ]] && ! grep -Eiq 'Cipher is \(NONE\)|no peer certificate|handshake failure|no cipher match|alert handshake failure' "${OUT}/openssl-null-anon.txt"; then
    NULL_CIPHER_CONFIRMED="true"
    add_finding "Confirmed NULL or anonymous cipher support" "high" "confirmed" "Restricted OpenSSL validation negotiated ${null_cipher}."
  else
    add_finding "testssl NULL or anonymous cipher observation not reproduced" "informational" "not confirmed" "Restricted OpenSSL validation did not negotiate a NULL/eNULL/aNULL cipher."
  fi
else
  printf 'No NULL/eNULL/aNULL indicators found in testssl output.\n' > "${OUT}/openssl-null-anon.txt"
fi

if legacy_tls_offered "${TESTSSL_FILES[@]}"; then
  LEGACY_TLS_STATUS="offered"
  add_finding "Legacy TLS protocol offered" "medium" "unvalidated" "testssl output indicates TLS 1.0 or TLS 1.1 may be offered."
fi

if [[ "${TLS12_RESULT}" == "completed" && "${TLS13_RESULT}" == "completed" && "${LEGACY_TLS_STATUS}" != "offered" && "${NULL_CIPHER_CONFIRMED}" != "true" && "${VERIFY_RETURN_CODE}" =~ ^0[[:space:]]+\(ok\) ]]; then
  TLS_POSTURE="appears modern based on successful TLS 1.2 and TLS 1.3 negotiation, with no contradictory validated evidence"
else
  TLS_POSTURE="review findings and warnings"
fi

findings_json="${OUT}/tls-findings.json"
{
  printf '[\n'
  for index in "${!FINDINGS[@]}"; do
    IFS='|' read -r title severity status description <<< "${FINDINGS[$index]}"
    [[ "${index}" -gt 0 ]] && printf ',\n'
    printf '  {\n'
    printf '    "title": "%s",\n' "$(json_escape "${title}")"
    printf '    "severity": "%s",\n' "$(json_escape "${severity}")"
    printf '    "status": "%s",\n' "$(json_escape "${status}")"
    printf '    "source": "phase-1-tls",\n'
    printf '    "description": "%s"\n' "$(json_escape "${description}")"
    printf '  }'
  done
  printf '\n]\n'
} > "${findings_json}"

cat > "${OUT}/tls-summary.md" <<EOF
# TLS Summary

- Target: ${TARGET_BASE_URL}
- Host: ${TARGET_HOST}
- Profile: ${PROFILE}
- testssl: ${TESTSSL_STATUS}
- OpenSSL TLS 1.2: ${TLS12_RESULT}
- OpenSSL TLS 1.2 cipher: ${TLS12_CIPHER:-not negotiated}
- OpenSSL TLS 1.3: ${TLS13_RESULT}
- OpenSSL TLS 1.3 cipher: ${TLS13_CIPHER:-not negotiated}
- Certificate subject: ${CERT_SUBJECT:-not parsed}
- Certificate issuer: ${CERT_ISSUER:-not parsed}
- Certificate dates: ${CERT_DATES:-not parsed}
- Verify return code: ${VERIFY_RETURN_CODE:-not parsed}
- NULL/anonymous cipher validation: ${NULL_VALIDATION_STATUS}
- Legacy TLS status: ${LEGACY_TLS_STATUS}
- TLS posture: ${TLS_POSTURE}
- Findings file: tls-findings.json
- Warnings: ${WARNINGS[*]:-none}
EOF

TLS_MESSAGE="TLS validation completed."
printf 'phase-1-tls completed\n'
