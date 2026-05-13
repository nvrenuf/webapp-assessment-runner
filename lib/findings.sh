#!/usr/bin/env bash
set -Eeuo pipefail

findings_dir() {
  local workspace="$1"
  local dir="${workspace}/reports/findings"
  mkdir -p "${dir}"
  printf '%s\n' "${dir}"
}

write_empty_findings() {
  local workspace="$1"
  local output
  output="$(findings_dir "${workspace}")/normalized-findings.json"
  printf '[]\n' > "${output}"
  printf '%s\n' "${output}"
}
