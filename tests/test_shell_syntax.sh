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
    --tester "Test Runner" \
    --output-root "${tmp_root}" \
    --yes
)"

[[ -d "${workspace}/config" ]]
[[ -f "${workspace}/config/target.env" ]]
[[ -f "${workspace}/config/scope.yaml" ]]
[[ -f "${workspace}/config/metadata.json" ]]
[[ -d "${workspace}/evidence/phase-0-preflight" ]]

./assess.sh --workspace "${workspace}" >/dev/null
./status.sh --workspace "${workspace}" >/dev/null
./report.sh --workspace "${workspace}" >/dev/null

[[ -f "${workspace}/status/phase-0-preflight.json" ]]
[[ -f "${workspace}/reports/report.md" ]]
