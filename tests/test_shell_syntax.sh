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

./assess.sh --workspace "${workspace}" >/dev/null
./status.sh --workspace "${workspace}" >/dev/null
./report.sh --workspace "${workspace}" >/dev/null

[[ -f "${workspace}/status/phase-0-preflight.json" ]]
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
