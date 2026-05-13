#!/usr/bin/env bash
set -Eeuo pipefail

log_line() {
  local level="$1"
  local message="$2"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s [%s] %s\n' "${ts}" "${level}" "${message}"
}

log_info() {
  log_line "INFO" "$*"
}

log_warn() {
  log_line "WARN" "$*"
}

log_error() {
  log_line "ERROR" "$*" >&2
}

workspace_log() {
  local workspace="$1"
  local message="$2"
  mkdir -p "${workspace}/logs"
  log_info "${message}" | tee -a "${workspace}/logs/runner.log" >/dev/null
}
