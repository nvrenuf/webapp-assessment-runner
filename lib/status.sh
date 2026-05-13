#!/usr/bin/env bash
set -Eeuo pipefail

write_status() {
  local workspace="$1"
  local name="$2"
  local state="$3"
  local message="$4"
  local status_dir="${workspace}/status"
  local status_file="${status_dir}/${name}.json"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  mkdir -p "${status_dir}"
  cat > "${status_file}" <<EOF
{
  "name": "$(json_escape "${name}")",
  "state": "$(json_escape "${state}")",
  "message": "$(json_escape "${message}")",
  "updated_at": "${ts}"
}
EOF
}

print_status_summary() {
  local workspace="$1"
  local status_dir="${workspace}/status"
  if [[ ! -d "${status_dir}" ]]; then
    printf 'No status directory found for workspace: %s\n' "${workspace}"
    return 0
  fi
  find "${status_dir}" -maxdepth 1 -type f -name '*.json' -print | sort
}
