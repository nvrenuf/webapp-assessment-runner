#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

bash -n install.sh init-assessment.sh assess.sh status.sh report.sh phases/*.sh lib/*.sh

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}" assessments/example-co' EXIT

workspace="$(
  ./init-assessment.sh \
    --company "Example Company" \
    --engagement "Smoke test" \
    --target "https://app.example.com" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"

[[ -d "${workspace}/config" ]]
[[ -f "${workspace}/config/target.env" ]]
[[ -f "${workspace}/config/scope.yaml" ]]
[[ -f "${workspace}/config/metadata.json" ]]
[[ -f "${workspace}/config/client-intake.yaml" ]]
grep -q "client_name: Example Company" "${workspace}/config/client-intake.yaml"
[[ -d "${workspace}/evidence/phase-0-preflight" ]]
grep -q 'AUTH_MODE="none"' "${workspace}/config/target.env"
grep -q 'AUTH_ENABLED="false"' "${workspace}/config/target.env"
grep -q '"auth_mode": "none"' "${workspace}/config/metadata.json"
grep -q '"auth_enabled": false' "${workspace}/config/metadata.json"

./status.sh --workspace "${workspace}" >/dev/null
./report.sh --workspace "${workspace}" >/dev/null

[[ -f "${workspace}/reports/report.md" ]]

for alias in none no false unauthenticated OFF; do
  alias_workspace="$(
    ./init-assessment.sh \
      --company "Alias Company" \
      --engagement "Auth alias ${alias}" \
      --target "https://${alias}.example.com" \
      --profile safe \
      --auth "${alias}" \
      --tester "Test Runner" \
      --output-root "${tmp_root}" \
      --yes
  )"
  grep -q 'AUTH_MODE="none"' "${alias_workspace}/config/target.env"
  grep -q 'AUTH_ENABLED="false"' "${alias_workspace}/config/target.env"
  grep -q '"auth_mode": "none"' "${alias_workspace}/config/metadata.json"
  grep -q '"auth_enabled": false' "${alias_workspace}/config/metadata.json"
done

for alias in placeholder yes true authenticated ON; do
  alias_workspace="$(
    ./init-assessment.sh \
      --company "Alias Company" \
      --engagement "Auth alias ${alias}" \
      --target "https://${alias}.example.com" \
      --profile safe \
      --auth "${alias}" \
      --tester "Test Runner" \
      --output-root "${tmp_root}" \
      --yes
  )"
  grep -q 'AUTH_MODE="placeholder"' "${alias_workspace}/config/target.env"
  grep -q 'AUTH_ENABLED="true"' "${alias_workspace}/config/target.env"
  grep -q '"auth_mode": "placeholder"' "${alias_workspace}/config/metadata.json"
  grep -q '"auth_enabled": true' "${alias_workspace}/config/metadata.json"
done

invalid_output="$(
  ./init-assessment.sh \
    --company "Alias Company" \
    --engagement "Invalid alias" \
    --target "https://invalid.example.com" \
    --auth potato \
    --output-root "${tmp_root}" \
    --yes 2>&1 || true
)"
grep -q 'error: --auth must be one of: none, placeholder, or an accepted alias' <<< "${invalid_output}"

missing_output="$(./phases/00-preflight.sh --workspace "${tmp_root}/missing" --yes 2>&1 || true)"
grep -q 'error: workspace does not exist:' <<< "${missing_output}"

fakebin="${tmp_root}/fakebin"
mkdir -p "${fakebin}"
real_python_bin="$(python3 - <<'PY'
import sys
print(sys.executable)
PY
)"

for tool in curl openssl nmap nikto nuclei jq python3 testssl zaproxy; do
  cat > "${fakebin}/${tool}" <<'EOF'
#!/usr/bin/env bash
printf '%s fake version\n' "$(basename "$0")"
EOF
  chmod +x "${fakebin}/${tool}"
done

cat > "${fakebin}/python3" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" || "\$#" -eq 0 ]]; then
  printf 'python3 fake version\n'
  exit 0
fi
exec "${real_python_bin}" "\$@"
EOF
chmod +x "${fakebin}/python3"

cat > "${fakebin}/openssl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" || "${1:-}" == "version" ]]; then
  printf 'OpenSSL fake 3.0.0\n'
  exit 0
fi
if [[ "${1:-}" == "x509" ]]; then
  printf 'notBefore=May 13 00:00:00 2026 GMT\n'
  printf 'notAfter=May 13 00:00:00 2027 GMT\n'
  exit 0
fi
if [[ "${1:-}" == "s_client" ]]; then
  args="$*"
  if [[ "${args}" == *"NULL:eNULL:aNULL"* ]]; then
    printf 'CONNECTED(00000003)\n'
    printf 'no peer certificate available\n'
    printf 'SSL handshake has read 0 bytes and written 7 bytes\n'
    printf 'Cipher is (NONE)\n'
    printf 'alert handshake failure\n'
    exit 1
  fi
  if [[ "${args}" == *"-tls1_3"* ]]; then
    printf 'CONNECTED(00000003)\n'
    printf 'subject=CN = example.com\n'
    printf 'issuer=C = US, O = Example CA\n'
    printf 'New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384\n'
    printf 'Verify return code: 0 (ok)\n'
    exit 0
  fi
  printf 'CONNECTED(00000003)\n'
  printf 'subject=CN = example.com\n'
  printf 'issuer=C = US, O = Example CA\n'
  printf 'New, TLSv1.2, Cipher is ECDHE-RSA-AES256-GCM-SHA384\n'
  printf 'Verify return code: 0 (ok)\n'
  exit 0
fi
printf 'OpenSSL fake 3.0.0\n'
EOF
chmod +x "${fakebin}/openssl"

cat > "${fakebin}/testssl" <<'EOF'
#!/usr/bin/env bash
logfile=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --logfile)
      logfile="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -n "${TESTSSL_FIXTURE:-}" ]]; then
  printf '%b\n' "${TESTSSL_FIXTURE}" | tee "${logfile}" >/dev/null
else
  {
    printf 'Testing protocols via sockets except NPN+ALPN\n'
    printf 'TLS 1.2 offered\n'
    printf 'TLS 1.3 offered\n'
    printf 'NULL ciphers offered: possible aNULL/eNULL concern\n'
  } | tee "${logfile}" >/dev/null
fi
printf 'testssl fake completed\n'
EOF
chmod +x "${fakebin}/testssl"

PATH="${fakebin}:${PATH}" ./install.sh --check-only >/dev/null

cat > "${fakebin}/dpkg" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--audit" ]]; then
  exit 0
fi
printf 'dpkg fake version\n'
EOF
chmod +x "${fakebin}/dpkg"

cat > "${fakebin}/apt-get" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "check" ]]; then
  printf 'Reading package lists... Done\n'
  exit 0
fi
printf 'apt-get fake version\n'
EOF
chmod +x "${fakebin}/apt-get"

cat > "${fakebin}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-n" ]]; then
  shift
fi
exec "$@"
EOF
chmod +x "${fakebin}/sudo"

cat > "${fakebin}/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "hosts" ]]; then
  printf '127.0.0.1 %s\n' "${2:-localhost}"
  exit 0
fi
exit 1
EOF
chmod +x "${fakebin}/getent"

cat > "${fakebin}/curl" <<'EOF'
#!/usr/bin/env bash
headers=""
body=""
redirects="false"
cors="false"
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -D)
      headers="$2"
      shift 2
      ;;
    -o)
      body="$2"
      shift 2
      ;;
    -IL|-LI)
      redirects="true"
      shift
      ;;
    -H)
      if [[ "${2:-}" == "Origin: https://evil.example.com" ]]; then
        cors="true"
      fi
      shift 2
      ;;
    --max-time)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
if [[ "${redirects}" == "true" ]]; then
  printf 'HTTP/1.1 301 Moved Permanently\r\nLocation: %s/\r\n\r\nHTTP/2 200 OK\r\nServer: fake\r\n\r\n' "${url}"
  exit 0
fi
if [[ "${cors}" == "true" ]]; then
  if [[ "${CORS_FIXTURE:-}" == "reflect" ]]; then
    printf 'HTTP/2 200 OK\r\nAccess-Control-Allow-Origin: https://evil.example.com\r\nVary: Origin\r\n\r\n' > "${headers}"
  elif [[ "${CORS_FIXTURE:-}" == "wildcard-credentials" ]]; then
    printf 'HTTP/2 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Credentials: true\r\nAccess-Control-Allow-Methods: GET, POST\r\nAccess-Control-Allow-Headers: X-Test\r\n\r\n' > "${headers}"
  else
    printf 'HTTP/2 200 OK\r\nServer: fake-cors-none\r\n\r\n' > "${headers}"
  fi
  exit 0
fi
if [[ "${url}" == *"/login" ]]; then
  {
    printf 'HTTP/2 200 OK\r\n'
    printf 'server: fake-login\r\n'
    printf 'CONTENT-SECURITY-POLICY: default-src '\''self'\''; script-src '\''self'\'' '\''unsafe-inline'\'' '\''unsafe-eval'\'' https://*.cdn.example; style-src '\''self'\'' '\''unsafe-inline'\''; frame-ancestors https://*.frames.example *\r\n'
    printf 'Strict-Transport-Security: max-age=31536000; includeSubDomains\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf 'Set-Cookie: sid=fake; HttpOnly; Secure\r\n'
    printf 'Access-Control-Allow-Origin: https://example.com\r\n'
    printf 'Vary: Origin\r\n'
    printf 'X-Test-URL: %s\r\n\r\n' "${url}"
  } > "${headers}"
else
  {
    printf 'HTTP/2 200 OK\r\n'
    printf 'Server: fake-base\r\n'
    printf 'X-Content-Type-Options: nosniff\r\n'
    printf 'Referrer-Policy: strict-origin-when-cross-origin\r\n'
    printf 'Permissions-Policy: geolocation=()\r\n'
    printf 'Cache-Control: max-age=60\r\n'
    printf 'Location: /next\r\n'
    printf 'Refresh: 0; url=/next\r\n'
    printf 'X-Test-URL: %s\r\n\r\n' "${url}"
  } > "${headers}"
fi
printf '<html><body>%s</body></html>\n' "${url}" > "${body}"
EOF
chmod +x "${fakebin}/curl"

cat > "${fakebin}/nikto" <<'EOF'
#!/usr/bin/env bash
output=""
host=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h)
      host="$2"
      shift 2
      ;;
    -output)
      output="$2"
      shift 2
      ;;
    -C)
      printf 'unsafe -C option should not be used\n' >&2
      exit 9
      ;;
    *)
      shift
      ;;
  esac
done
{
  printf -- '- Nikto v2.5.0\n'
  printf -- '+ Target URL: %s\n' "${host}"
  printf -- '+ The anti-clickjacking X-Frame-Options header is not present.\n'
  printf -- '+ The X-Content-Type-Options header is not present.\n'
  printf -- '+ Permissions-Policy header is not present.\n'
  printf -- '+ Referrer-Policy header is not present.\n'
  printf -- '+ Uncommon header '\''Refresh'\'' found, with contents: 0; url=/next\n'
  printf -- '+ Server banner changed from '\''awselb/2.0'\'' to '\''private'\''\n'
  printf -- '+ SSL Certificate Subject Wildcard *.example.com\n'
  printf -- '+ ERROR: Failed to check for updates: 403 Forbidden\n'
  printf -- '+ No CGI Directories found (use '\''-C all'\'' to force check all possible dirs)\n'
} > "${output}"
printf 'mock nikto scanned %s\n' "${host}"
EOF
chmod +x "${fakebin}/nikto"

preflight_workspace="$(
  ./init-assessment.sh \
    --company "Preflight Company" \
    --engagement "Preflight success" \
    --target "https://preflight.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"

PATH="${fakebin}:${PATH}" ./phases/00-preflight.sh --workspace "${preflight_workspace}" --yes >/dev/null
[[ -f "${preflight_workspace}/status/phase-0-preflight.status" ]]
[[ -f "${preflight_workspace}/evidence/phase-0-preflight/preflight-summary.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-0-preflight/tool-versions.txt" ]]
[[ -f "${preflight_workspace}/config/tool-paths.env" ]]
grep -q '^STATUS=success$' "${preflight_workspace}/status/phase-0-preflight.status"
grep -q 'APT dependency check: passed' "${preflight_workspace}/evidence/phase-0-preflight/preflight-summary.md"
grep -q '^CURL_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^OPENSSL_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^NMAP_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^NIKTO_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^NUCLEI_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^JQ_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^PYTHON_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^TESTSSL_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^ZAP_BIN=' "${preflight_workspace}/config/tool-paths.env"

PATH="${fakebin}:${PATH}" ./phases/02-headers.sh --workspace "${preflight_workspace}" --yes >/dev/null
[[ -f "${preflight_workspace}/status/phase-2-headers.status" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/base-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/base-body-latest.html" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/base-redirects-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/base-cors-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/login-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/login-body-latest.html" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/login-redirects-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/login-cors-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/headers-findings.json" ]]
first_headers_raw_count="$(find "${preflight_workspace}/evidence/phase-2-headers" -maxdepth 1 -type f \( -name 'base-headers-[0-9]*T[0-9]*Z.txt' -o -name 'login-headers-[0-9]*T[0-9]*Z.txt' \) | wc -l)"
[[ "${first_headers_raw_count}" -eq 2 ]]
first_cors_raw_count="$(find "${preflight_workspace}/evidence/phase-2-headers" -maxdepth 1 -type f -name '*-cors-headers-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${first_cors_raw_count}" -eq 2 ]]
grep -q '^STATUS=success$' "${preflight_workspace}/status/phase-2-headers.status"
grep -q 'base: HTTP/2 200 OK' "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md"
grep -q 'login: HTTP/2 200 OK' "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md"
grep -q 'HTTP/1.1 301 Moved Permanently' "${preflight_workspace}/evidence/phase-2-headers/base-redirects-latest.txt"
grep -q $'login\tcontent-security-policy\tdefault-src '\''self'\''; script-src '\''self'\'' '\''unsafe-inline'\'' '\''unsafe-eval'\''' "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.txt"
grep -q $'login\tx-content-type-options\tMISSING' "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.txt"
grep -q $'login\tstrict-transport-security\tmax-age=31536000; includeSubDomains' "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.txt"
grep -q $'base\tpermissions-policy\tgeolocation=()' "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.txt"
grep -q 'HSTS: present (max-age=31536000)' "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.md"
grep -q 'Missing recommended headers: x-content-type-options referrer-policy permissions-policy' "${preflight_workspace}/evidence/phase-2-headers/security-header-summary.md"
grep -q 'security header markdown summary: security-header-summary.md' "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md"
grep -q $'base\tcsp-present\tmissing\tContent-Security-Policy header is not present' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tscript-src-unsafe-inline\tobserved\tscript-src includes '\''unsafe-inline'\''' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tscript-src-unsafe-eval\tobserved\tscript-src includes '\''unsafe-eval'\''' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tstyle-src-unsafe-inline\tobserved\tstyle-src includes '\''unsafe-inline'\''' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tmissing-form-action\tmissing\tform-action directive is not defined' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tmissing-base-uri\tmissing\tbase-uri directive is not defined' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tbroad-wildcard-sources\tneeds review' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tbroad-frame-ancestors\tneeds review\tframe-ancestors contains wildcard source' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q $'login\tdefault-src\tobserved\tdefault-src is defined' "${preflight_workspace}/evidence/phase-2-headers/csp-analysis.txt"
grep -q 'CSP markdown analysis: csp-analysis.md' "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md"
grep -q $'base\tarbitrary-origin-reflection\tnot observed\tACAO=MISSING' "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.txt"
grep -q $'login\trisky-cors-combination\tnot observed\tACAO=MISSING; ACAC=MISSING' "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.txt"
grep -q 'CORS markdown analysis: cors-analysis.md' "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md"
grep -q 'structured findings: headers-findings.json' "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md"
FINDINGS_FILE="${preflight_workspace}/evidence/phase-2-headers/headers-findings.json" python3 - <<'PY'
import json
import os

with open(os.environ["FINDINGS_FILE"], encoding="utf-8") as handle:
    findings = json.load(handle)

def has(title, severity=None, status=None):
    for finding in findings:
        if finding["title"] != title:
            continue
        if severity is not None and finding["severity"] != severity:
            continue
        if status is not None and finding["status"] != status:
            continue
        return True
    return False

assert has("Missing X-Content-Type-Options on login", "low", "confirmed")
assert has("CSP permits unsafe JavaScript evaluation on login", "medium", "confirmed")
assert has("CORS arbitrary origin reflection not observed on login", "informational", "not_observed")
assert has("Base URL returns redirect response", "informational", "observed")
assert not any(f["title"] == "Missing CSP on base" for f in findings)
PY
sleep 1
CORS_FIXTURE=reflect PATH="${fakebin}:${PATH}" ./phases/02-headers.sh --workspace "${preflight_workspace}" --yes >/dev/null
second_headers_raw_count="$(find "${preflight_workspace}/evidence/phase-2-headers" -maxdepth 1 -type f \( -name 'base-headers-[0-9]*T[0-9]*Z.txt' -o -name 'login-headers-[0-9]*T[0-9]*Z.txt' \) | wc -l)"
second_cors_raw_count="$(find "${preflight_workspace}/evidence/phase-2-headers" -maxdepth 1 -type f -name '*-cors-headers-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${second_headers_raw_count}" -gt "${first_headers_raw_count}" ]]
[[ "${second_cors_raw_count}" -gt "${first_cors_raw_count}" ]]
grep -q $'base\tarbitrary-origin-reflection\tobserved\tACAO=https://evil.example.com' "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.txt"
FINDINGS_FILE="${preflight_workspace}/evidence/phase-2-headers/headers-findings.json" python3 - <<'PY'
import json
import os

with open(os.environ["FINDINGS_FILE"], encoding="utf-8") as handle:
    findings = json.load(handle)
assert any(
    finding["title"] == "CORS reflects arbitrary Origin on login"
    and finding["severity"] == "medium"
    and finding["status"] == "confirmed"
    for finding in findings
)
PY
CORS_FIXTURE=wildcard-credentials PATH="${fakebin}:${PATH}" ./phases/02-headers.sh --workspace "${preflight_workspace}" --yes --clean >/dev/null
clean_headers_raw_count="$(find "${preflight_workspace}/evidence/phase-2-headers" -maxdepth 1 -type f \( -name 'base-headers-[0-9]*T[0-9]*Z.txt' -o -name 'login-headers-[0-9]*T[0-9]*Z.txt' \) | wc -l)"
clean_cors_raw_count="$(find "${preflight_workspace}/evidence/phase-2-headers" -maxdepth 1 -type f -name '*-cors-headers-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${clean_headers_raw_count}" -eq 2 ]]
[[ "${clean_cors_raw_count}" -eq 2 ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/base-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/login-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/base-cors-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/login-cors-headers-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-2-headers/headers-summary.md" ]]
grep -Fq $'base\twildcard-origin\tobserved\tACAO=*' "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.txt"
grep -q $'base\tcredentials-allowed\tobserved\tACAC=true' "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.txt"
grep -Fq $'base\trisky-cors-combination\tobserved\tACAO=*; ACAC=true' "${preflight_workspace}/evidence/phase-2-headers/cors-analysis.txt"
FINDINGS_FILE="${preflight_workspace}/evidence/phase-2-headers/headers-findings.json" python3 - <<'PY'
import json
import os

with open(os.environ["FINDINGS_FILE"], encoding="utf-8") as handle:
    findings = json.load(handle)
assert any(
    finding["title"] == "CORS permits arbitrary origin with credentials on login"
    and finding["severity"] == "high"
    and finding["status"] == "confirmed"
    for finding in findings
)
PY

nikto_output="${tmp_root}/nikto-output.txt"
PATH="${fakebin}:${PATH}" ./phases/03-nikto.sh --workspace "${preflight_workspace}" --yes --verbose >"${nikto_output}"
grep -q '^phase-3-nikto starting$' "${nikto_output}"
grep -q "^workspace: ${preflight_workspace}$" "${nikto_output}"
grep -q "^evidence directory: ${preflight_workspace}/evidence/phase-3-nikto$" "${nikto_output}"
grep -q "^status file: ${preflight_workspace}/status/phase-3-nikto.status$" "${nikto_output}"
grep -q '^target mode: login$' "${nikto_output}"
grep -q '^  - login: https://preflight.example.com/login$' "${nikto_output}"
grep -q '^Nikto binary: ' "${nikto_output}"
grep -q '^NIKTO_PAUSE: 5$' "${nikto_output}"
grep -q '^NIKTO_MAXTIME: 2h$' "${nikto_output}"
grep -q '^NIKTO_TUNING: x6$' "${nikto_output}"
grep -q '^raw output file: ' "${nikto_output}"
grep -q '^console log file: ' "${nikto_output}"
grep -q '^heartbeat file: ' "${nikto_output}"
grep -q '^PID file: ' "${nikto_output}"
grep -q 'tail -f ".*/nikto-login-console-[0-9]*T[0-9]*Z.txt"' "${nikto_output}"
grep -q 'tail -f ".*/nikto-login-heartbeat-[0-9]*T[0-9]*Z.txt"' "${nikto_output}"
grep -Fq "  ./status.sh --workspace \"${preflight_workspace}\"" "${nikto_output}"
grep -q '^summary path: ' "${nikto_output}"
grep -q '^findings path: ' "${nikto_output}"
grep -q '^findings by severity:$' "${nikto_output}"
grep -Eq '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T.* login (running|stopped) elapsed=[0-9]{2}:[0-9]{2}:[0-9]{2} raw_size=.* raw_lines=[0-9]+ console_size=.*' "${nikto_output}"
[[ -f "${preflight_workspace}/status/phase-3-nikto.status" ]]
[[ -f "${preflight_workspace}/status/phase-3-nikto.json" ]]
[[ ! -e "${preflight_workspace}/status/phase-3-nikto-login.pid" ]]
[[ -f "${preflight_workspace}/evidence/phase-3-nikto/nikto-login-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-3-nikto/nikto-login-console-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-3-nikto/nikto-login-heartbeat-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-3-nikto/nikto-summary.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-3-nikto/nikto-findings.json" ]]
grep -Eq '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T.* login (running|stopped) elapsed=[0-9]{2}:[0-9]{2}:[0-9]{2} raw_size=.* raw_lines=[0-9]+ console_size=.*' "${preflight_workspace}/evidence/phase-3-nikto/nikto-login-heartbeat-latest.txt"
first_nikto_raw_count="$(find "${preflight_workspace}/evidence/phase-3-nikto" -maxdepth 1 -type f -name 'nikto-login-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${first_nikto_raw_count}" -eq 1 ]]
grep -q '^STATUS=success$' "${preflight_workspace}/status/phase-3-nikto.status"
grep -q '^TARGET_MODE=login$' "${preflight_workspace}/status/phase-3-nikto.status"
grep -q '^NIKTO_TUNING=x6$' "${preflight_workspace}/status/phase-3-nikto.status"
grep -q 'target mode: login' "${preflight_workspace}/evidence/phase-3-nikto/nikto-summary.md"
NIKTO_FINDINGS_FILE="${preflight_workspace}/evidence/phase-3-nikto/nikto-findings.json" python3 - <<'PY'
import json
import os

with open(os.environ["NIKTO_FINDINGS_FILE"], encoding="utf-8") as handle:
    findings = json.load(handle)

def has(title, severity=None, status=None, category=None):
    for finding in findings:
        if finding["title"] != title:
            continue
        if severity is not None and finding["severity"] != severity:
            continue
        if status is not None and finding["status"] != status:
            continue
        if category is not None and finding["category"] != category:
            continue
        return True
    return False

assert has("Missing X-Content-Type-Options", "low", "confirmed", "headers")
assert has("Missing Permissions-Policy", "low", "confirmed", "headers")
assert has("Missing Referrer-Policy", "low", "confirmed", "headers")
assert has("Uncommon Refresh header observed", "low", "observed", "headers")
assert has("Server banner changed during scan", "informational", "informational", "server")
assert has("Wildcard certificate observed", "informational", "informational", "tls")
assert has("Nikto update check failed", "informational", "informational", "tooling")
assert has("No CGI directories found", "informational", "informational", "directories")
assert not any(f["severity"] == "high" for f in findings)
PY
sleep 1
PATH="${fakebin}:${PATH}" ./phases/03-nikto.sh --workspace "${preflight_workspace}" --yes >/dev/null
second_nikto_raw_count="$(find "${preflight_workspace}/evidence/phase-3-nikto" -maxdepth 1 -type f -name 'nikto-login-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${second_nikto_raw_count}" -gt "${first_nikto_raw_count}" ]]
[[ ! -e "${preflight_workspace}/status/phase-3-nikto-login.pid" ]]
PATH="${fakebin}:${PATH}" ./phases/03-nikto.sh --workspace "${preflight_workspace}" --yes --clean >/dev/null
clean_nikto_raw_count="$(find "${preflight_workspace}/evidence/phase-3-nikto" -maxdepth 1 -type f -name 'nikto-login-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${clean_nikto_raw_count}" -eq 1 ]]
[[ -f "${preflight_workspace}/evidence/phase-3-nikto/nikto-login-latest.txt" ]]
[[ ! -e "${preflight_workspace}/status/phase-3-nikto-login.pid" ]]

PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${preflight_workspace}" --yes >/dev/null
[[ -f "${preflight_workspace}/status/phase-1-tls.status" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/tls-summary.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/tls-findings.json" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/testssl-fast-latest.log" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/testssl-fast-console-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/openssl-tls12-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/openssl-tls13-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/openssl-null-anon-latest.txt" ]]
first_tls_raw_count="$(find "${preflight_workspace}/evidence/phase-1-tls" -maxdepth 1 -type f -name 'testssl-fast-[0-9]*T[0-9]*Z.log' | wc -l)"
first_null_raw_count="$(find "${preflight_workspace}/evidence/phase-1-tls" -maxdepth 1 -type f -name 'openssl-null-anon-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${first_tls_raw_count}" -eq 1 ]]
[[ "${first_null_raw_count}" -eq 1 ]]
grep -q '^STATUS=success$' "${preflight_workspace}/status/phase-1-tls.status"
grep -q 'OpenSSL TLS 1.2 cipher: ECDHE-RSA-AES256-GCM-SHA384' "${preflight_workspace}/evidence/phase-1-tls/tls-summary.md"
grep -q 'OpenSSL TLS 1.3 cipher: TLS_AES_256_GCM_SHA384' "${preflight_workspace}/evidence/phase-1-tls/tls-summary.md"
grep -q '"title": "testssl NULL or anonymous cipher observation not reproduced"' "${preflight_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q '"status": "not confirmed"' "${preflight_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q 'Cipher is (NONE)' "${preflight_workspace}/evidence/phase-1-tls/openssl-null-anon-latest.txt"
sleep 1
PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${preflight_workspace}" --yes >/dev/null
second_tls_raw_count="$(find "${preflight_workspace}/evidence/phase-1-tls" -maxdepth 1 -type f -name 'testssl-fast-[0-9]*T[0-9]*Z.log' | wc -l)"
second_null_raw_count="$(find "${preflight_workspace}/evidence/phase-1-tls" -maxdepth 1 -type f -name 'openssl-null-anon-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${second_tls_raw_count}" -gt "${first_tls_raw_count}" ]]
[[ "${second_null_raw_count}" -gt "${first_null_raw_count}" ]]
grep -q '^STATUS=success$' "${preflight_workspace}/status/phase-1-tls.status"
printf 'legacy\n' > "${preflight_workspace}/evidence/phase-1-tls/openssl-null-anon.txt"
printf 'legacy\n' > "${preflight_workspace}/evidence/phase-1-tls/openssl-tls12.txt"
printf 'legacy\n' > "${preflight_workspace}/evidence/phase-1-tls/openssl-tls13.txt"
printf 'legacy\n' > "${preflight_workspace}/evidence/phase-1-tls/testssl-fast-console.txt"
printf 'legacy\n' > "${preflight_workspace}/evidence/phase-1-tls/testssl-fast.log"
PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${preflight_workspace}" --yes --clean >/dev/null
clean_tls_raw_count="$(find "${preflight_workspace}/evidence/phase-1-tls" -maxdepth 1 -type f -name 'testssl-fast-[0-9]*T[0-9]*Z.log' | wc -l)"
clean_null_raw_count="$(find "${preflight_workspace}/evidence/phase-1-tls" -maxdepth 1 -type f -name 'openssl-null-anon-[0-9]*T[0-9]*Z.txt' | wc -l)"
[[ "${clean_tls_raw_count}" -eq 1 ]]
[[ "${clean_null_raw_count}" -eq 1 ]]
[[ ! -e "${preflight_workspace}/evidence/phase-1-tls/openssl-null-anon.txt" ]]
[[ ! -e "${preflight_workspace}/evidence/phase-1-tls/openssl-tls12.txt" ]]
[[ ! -e "${preflight_workspace}/evidence/phase-1-tls/openssl-tls13.txt" ]]
[[ ! -e "${preflight_workspace}/evidence/phase-1-tls/testssl-fast-console.txt" ]]
[[ ! -e "${preflight_workspace}/evidence/phase-1-tls/testssl-fast.log" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/testssl-fast-latest.log" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/testssl-fast-console-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/openssl-tls12-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/openssl-tls13-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/openssl-null-anon-latest.txt" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/tls-summary.md" ]]
[[ -f "${preflight_workspace}/evidence/phase-1-tls/tls-findings.json" ]]

tls_not_offered_workspace="$(
  ./init-assessment.sh \
    --company "TLS Fixtures" \
    --engagement "Legacy not offered" \
    --target "https://tls-not-offered.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
TESTSSL_FIXTURE=$'TLS 1.0 not offered\nTLS 1.1 not offered\nTLS 1.2 offered\nTLS 1.3 offered' PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${tls_not_offered_workspace}" --yes >/dev/null
! grep -q '"title": "Legacy TLS protocol offered"' "${tls_not_offered_workspace}/evidence/phase-1-tls/tls-findings.json"
! grep -q '"severity": "medium"' "${tls_not_offered_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q 'TLS posture: appears modern' "${tls_not_offered_workspace}/evidence/phase-1-tls/tls-summary.md"

tls_not_available_workspace="$(
  ./init-assessment.sh \
    --company "TLS Fixtures" \
    --engagement "Legacy negative variants" \
    --target "https://tls-negative.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
TESTSSL_FIXTURE=$'TLS 1.0 not available\nTLS 1.1 not supported\nTLS 1.2 offered\nTLS 1.3 offered\nnot vulnerable' PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${tls_not_available_workspace}" --yes >/dev/null
! grep -q '"title": "Legacy TLS protocol offered"' "${tls_not_available_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q 'TLS posture: appears modern' "${tls_not_available_workspace}/evidence/phase-1-tls/tls-summary.md"

tls10_offered_workspace="$(
  ./init-assessment.sh \
    --company "TLS Fixtures" \
    --engagement "TLS 1.0 offered" \
    --target "https://tls10-offered.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
TESTSSL_FIXTURE=$'TLS 1.0 offered\nTLS 1.1 not offered\nTLS 1.2 offered\nTLS 1.3 offered' PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${tls10_offered_workspace}" --yes >/dev/null
grep -q '"title": "Legacy TLS protocol offered"' "${tls10_offered_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q '"severity": "medium"' "${tls10_offered_workspace}/evidence/phase-1-tls/tls-findings.json"

tls11_offered_workspace="$(
  ./init-assessment.sh \
    --company "TLS Fixtures" \
    --engagement "TLS 1.1 offered" \
    --target "https://tls11-offered.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
TESTSSL_FIXTURE=$'TLS 1.0 not offered\nTLS 1.1 offered\nTLS 1.2 offered\nTLS 1.3 offered' PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${tls11_offered_workspace}" --yes >/dev/null
grep -q '"title": "Legacy TLS protocol offered"' "${tls11_offered_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q '"severity": "medium"' "${tls11_offered_workspace}/evidence/phase-1-tls/tls-findings.json"

tls_modern_workspace="$(
  ./init-assessment.sh \
    --company "TLS Fixtures" \
    --engagement "Modern TLS only" \
    --target "https://tls-modern.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
TESTSSL_FIXTURE=$'TLS 1.2 offered\nTLS 1.3 offered' PATH="${fakebin}:${PATH}" ./phases/01-tls.sh --workspace "${tls_modern_workspace}" --yes >/dev/null
! grep -q '"title": "Legacy TLS protocol offered"' "${tls_modern_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q '"TLS 1.2 negotiated AEAD cipher"' "${tls_modern_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q '"TLS 1.3 negotiated AEAD cipher"' "${tls_modern_workspace}/evidence/phase-1-tls/tls-findings.json"
grep -q 'TLS posture: appears modern' "${tls_modern_workspace}/evidence/phase-1-tls/tls-summary.md"

regression_workspace="$(
  ./init-assessment.sh \
    --company "Example Co" \
    --company-slug example-co \
    --engagement "Example Staging" \
    --target https://example.com \
    --login-path /login \
    --environment staging \
    --profile safe \
    --auth no \
    --tester "Tester" \
    --yes
)"
target_env="${regression_workspace}/config/target.env"
for required_var in \
  COMPANY_NAME \
  COMPANY_SLUG \
  ENGAGEMENT_NAME \
  TARGET_BASE_URL \
  TARGET_HOST \
  LOGIN_PATH \
  LOGIN_URL \
  ENVIRONMENT \
  PROFILE \
  AUTH_MODE \
  AUTH_ENABLED \
  TESTER \
  RUN_ID \
  WORKSPACE; do
  grep -q "^${required_var}=\"" "${target_env}"
done
grep -q '^COMPANY_NAME="Example Co"$' "${target_env}"
grep -q '^COMPANY_SLUG="example-co"$' "${target_env}"
grep -q '^ENGAGEMENT_NAME="Example Staging"$' "${target_env}"
grep -q '^TARGET_BASE_URL="https://example.com"$' "${target_env}"
grep -q '^TARGET_HOST="example.com"$' "${target_env}"
grep -q '^LOGIN_PATH="/login"$' "${target_env}"
grep -q '^LOGIN_URL="https://example.com/login"$' "${target_env}"
grep -q '^AUTH_MODE="none"$' "${target_env}"
grep -q '^AUTH_ENABLED="false"$' "${target_env}"
grep -q '"company_name": "Example Co"' "${regression_workspace}/config/metadata.json"
grep -q '"engagement_name": "Example Staging"' "${regression_workspace}/config/metadata.json"
grep -q '"target_base_url": "https://example.com"' "${regression_workspace}/config/metadata.json"
regression_output="$(PATH="${fakebin}:${PATH}" ./phases/00-preflight.sh --workspace "${regression_workspace}" --yes 2>&1)"
grep -q 'phase-0-preflight completed' <<< "${regression_output}"
[[ -f "${regression_workspace}/status/phase-0-preflight.status" ]]
! grep -q '/status' <<< "${regression_output}"

legacy_workspace="${tmp_root}/legacy-workspace"
mkdir -p "${legacy_workspace}/config" "${legacy_workspace}/status"
cat > "${legacy_workspace}/config/target.env" <<'EOF'
COMPANY="Example Co"
COMPANY_SLUG="example-co"
ENGAGEMENT="Example Staging"
TARGET="https://example.com"
LOGIN_PATH="/login"
ENVIRONMENT="staging"
PROFILE="safe"
AUTH_MODE="none"
AUTH_ENABLED="false"
TESTER="Tester"
EOF
legacy_output="$(PATH="${fakebin}:${PATH}" ./phases/00-preflight.sh --workspace "${legacy_workspace}" --yes 2>&1 || true)"
grep -q 'error: missing required target config values:' <<< "${legacy_output}"
! grep -q 'mkdir: cannot create directory' <<< "${legacy_output}"
! grep -q '/status' <<< "${legacy_output}"
grep -q '^STATUS=failure$' "${legacy_workspace}/status/phase-0-preflight.status"

apt_permission_workspace="$(
  ./init-assessment.sh \
    --company "APT Permission Company" \
    --engagement "APT permission warning" \
    --target "https://apt-permission.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
cat > "${fakebin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo: a password is required\n' >&2
exit 1
EOF
chmod +x "${fakebin}/sudo"
apt_permission_output="$(PATH="${fakebin}:${PATH}" ./phases/00-preflight.sh --workspace "${apt_permission_workspace}" --yes 2>&1)"
grep -q 'phase-0-preflight completed' <<< "${apt_permission_output}"
grep -q '^STATUS=success$' "${apt_permission_workspace}/status/phase-0-preflight.status"
grep -q 'APT dependency check skipped because passwordless sudo is unavailable. Run `sudo apt-get check` manually for full package-health validation.' "${apt_permission_workspace}/evidence/phase-0-preflight/preflight-summary.md"
grep -q 'Run `sudo apt-get check` manually for full package-health validation.' "${apt_permission_workspace}/evidence/phase-0-preflight/apt-get-check.txt"

apt_failure_workspace="$(
  ./init-assessment.sh \
    --company "APT Failure Company" \
    --engagement "APT dependency failure" \
    --target "https://apt-failure.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
cat > "${fakebin}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-n" ]]; then
  shift
fi
if [[ "${1:-}" == "apt-get" && "${2:-}" == "check" ]]; then
  printf 'The following packages have unmet dependencies:\n'
  printf ' broken-package : Depends: missing-package but it is not installable\n'
  exit 100
fi
exec "$@"
EOF
chmod +x "${fakebin}/sudo"
apt_failure_output="$(PATH="${fakebin}:${PATH}" ./phases/00-preflight.sh --workspace "${apt_failure_workspace}" --yes 2>&1 || true)"
grep -q 'error: sudo apt-get check reported package dependency errors.' <<< "${apt_failure_output}"
grep -q '^STATUS=failure$' "${apt_failure_workspace}/status/phase-0-preflight.status"
grep -q 'unmet dependencies' "${apt_failure_workspace}/evidence/phase-0-preflight/apt-get-check.txt"

cat > "${fakebin}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-n" ]]; then
  shift
fi
exec "$@"
EOF
chmod +x "${fakebin}/sudo"

failure_workspace="$(
  ./init-assessment.sh \
    --company "Preflight Company" \
    --engagement "Preflight failure" \
    --target "https://failure.example.com" \
    --login-path "/login" \
    --profile safe \
    --auth none \
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"
rm -f "${fakebin}/nmap"
failure_output="$(PATH="${fakebin}:${PATH}" ./phases/00-preflight.sh --workspace "${failure_workspace}" --yes 2>&1 || true)"
grep -q 'error: required tool missing: nmap' <<< "${failure_output}"
grep -q '^STATUS=failure$' "${failure_workspace}/status/phase-0-preflight.status"
grep -q "MESSAGE='required tool missing: nmap'" "${failure_workspace}/status/phase-0-preflight.status"
