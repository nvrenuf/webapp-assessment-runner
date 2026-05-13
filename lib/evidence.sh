#!/usr/bin/env bash
set -Eeuo pipefail

phase_evidence_dir() {
  local workspace="$1"
  local phase_dir="$2"
  local evidence_dir="${workspace}/evidence/${phase_dir}"
  mkdir -p "${evidence_dir}"
  printf '%s\n' "${evidence_dir}"
}

write_phase_note() {
  local workspace="$1"
  local phase_dir="$2"
  local note="$3"
  local evidence_dir
  evidence_dir="$(phase_evidence_dir "${workspace}" "${phase_dir}")"
  printf '%s\n' "${note}" > "${evidence_dir}/README.txt"
}
