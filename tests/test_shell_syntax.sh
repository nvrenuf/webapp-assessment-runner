#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

bash -n install.sh init-assessment.sh assess.sh status.sh report.sh phases/*.sh lib/*.sh

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT

workspace="$(
  ./init-assessment.sh \
    --company "Example Company" \
    --engagement "Smoke test" \
    --target "https://app.example.test" \
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
[[ -d "${workspace}/evidence/phase-0-preflight" ]]
grep -q 'AUTH_MODE="none"' "${workspace}/config/target.env"
grep -q 'AUTH_ENABLED="false"' "${workspace}/config/target.env"
grep -q '"auth_mode": "none"' "${workspace}/config/metadata.json"
grep -q '"auth_enabled": false' "${workspace}/config/metadata.json"

./assess.sh --workspace "${workspace}" --skip-preflight >/dev/null
./status.sh --workspace "${workspace}" >/dev/null
./report.sh --workspace "${workspace}" >/dev/null

[[ -f "${workspace}/status/phase-1-tls.json" ]]
[[ -f "${workspace}/reports/report.md" ]]

for alias in none no false unauthenticated OFF; do
  alias_workspace="$(
    ./init-assessment.sh \
      --company "Alias Company" \
      --engagement "Auth alias ${alias}" \
      --target "https://${alias}.example.test" \
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
      --target "https://${alias}.example.test" \
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
    --target "https://invalid.example.test" \
    --auth potato \
    --output-root "${tmp_root}" \
    --yes 2>&1 || true
)"
grep -q 'error: --auth must be one of: none, placeholder, or an accepted alias' <<< "${invalid_output}"

missing_output="$(./phases/00-preflight.sh --workspace "${tmp_root}/missing" --yes 2>&1 || true)"
grep -q 'error: workspace does not exist:' <<< "${missing_output}"

fakebin="${tmp_root}/fakebin"
mkdir -p "${fakebin}"

for tool in openssl nmap nikto nuclei jq python3 testssl zaproxy; do
  cat > "${fakebin}/${tool}" <<'EOF'
#!/usr/bin/env bash
printf '%s fake version\n' "$(basename "$0")"
EOF
  chmod +x "${fakebin}/${tool}"
done

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
while [[ $# -gt 0 ]]; do
  case "$1" in
    -D)
      headers="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'HTTP/1.1 200 OK\r\nServer: fake\r\n\r\n' > "${headers}"
EOF
chmod +x "${fakebin}/curl"

preflight_workspace="$(
  ./init-assessment.sh \
    --company "Preflight Company" \
    --engagement "Preflight success" \
    --target "https://preflight.example.test" \
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
grep -q '^CURL_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^OPENSSL_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^NMAP_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^NIKTO_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^NUCLEI_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^JQ_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^PYTHON_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^TESTSSL_BIN=' "${preflight_workspace}/config/tool-paths.env"
grep -q '^ZAP_BIN=' "${preflight_workspace}/config/tool-paths.env"

failure_workspace="$(
  ./init-assessment.sh \
    --company "Preflight Company" \
    --engagement "Preflight failure" \
    --target "https://failure.example.test" \
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
