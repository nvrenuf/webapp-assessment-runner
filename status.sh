#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/status.sh
source "${SCRIPT_DIR}/lib/status.sh"

usage() {
  printf 'Usage: ./status.sh --workspace PATH\n'
}

print_phase3_active_nikto() {
  local workspace="$1"
  local status_dir="${workspace}/status"
  local evidence_dir="${workspace}/evidence/phase-3-nikto"
  local found="false"
  local pid_file pid label heartbeat_latest console_latest heartbeat_timestamp heartbeat_line
  shopt -s nullglob
  for pid_file in "${status_dir}"/phase-3-nikto-*.pid; do
    pid="$(cat "${pid_file}" 2>/dev/null || true)"
    label="${pid_file##*/phase-3-nikto-}"
    label="${label%.pid}"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      if [[ "${found}" == "false" ]]; then
        printf '\nActive Phase 3 Nikto scan(s):\n'
        found="true"
      fi
      heartbeat_latest="${evidence_dir}/nikto-${label}-heartbeat-latest.txt"
      console_latest="${evidence_dir}/nikto-${label}-console-latest.txt"
      if [[ ! -f "${heartbeat_latest}" ]]; then
        heartbeat_latest="$(find "${evidence_dir}" -maxdepth 1 -type f -name "nikto-${label}-heartbeat-[0-9]*T[0-9]*Z.txt" -print 2>/dev/null | sort | tail -n 1)"
      fi
      if [[ ! -f "${console_latest}" ]]; then
        console_latest="$(find "${evidence_dir}" -maxdepth 1 -type f -name "nikto-${label}-console-[0-9]*T[0-9]*Z.txt" -print 2>/dev/null | sort | tail -n 1)"
      fi
      heartbeat_timestamp=""
      heartbeat_line=""
      if [[ -f "${heartbeat_latest}" ]]; then
        heartbeat_timestamp="$(date -u -r "${heartbeat_latest}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)"
        heartbeat_line="$(tail -n 1 "${heartbeat_latest}" 2>/dev/null || true)"
      fi
      printf '%s\n' "- label: ${label}"
      printf '  PID: %s\n' "${pid}"
      printf '  PID file: %s\n' "${pid_file}"
      printf '  heartbeat latest: %s\n' "${heartbeat_latest}"
      if [[ -n "${heartbeat_timestamp}" ]]; then
        printf '  heartbeat updated UTC: %s\n' "${heartbeat_timestamp}"
      fi
      if [[ -n "${heartbeat_line}" ]]; then
        printf '  heartbeat last line: %s\n' "${heartbeat_line}"
      fi
      printf '  console latest: %s\n' "${console_latest}"
      printf '  monitor: tail -f "%s"\n' "${heartbeat_latest}"
      printf '  monitor: tail -f "%s"\n' "${console_latest}"
    fi
  done
  shopt -u nullglob
}

if ! parse_workspace_arg "$@"; then
  usage
  exit 0
fi

validate_workspace "${WORKSPACE}"
print_status_summary "${WORKSPACE}"
print_phase3_active_nikto "${WORKSPACE}"
