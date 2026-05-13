#!/usr/bin/env bash
set -Eeuo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${COMMON_DIR}/.." && pwd)"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
}

slugify() {
  local value="$1"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "${value}" | sed -E 's#https?://##; s#[^a-z0-9]+#-#g; s#^-+##; s#-+$##')"
  if [[ -z "${value}" ]]; then
    die "could not create slug from empty value"
  fi
  printf '%s\n' "${value}"
}

utc_run_id() {
  date -u '+%Y%m%dT%H%M%SZ'
}

absolute_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "$(pwd)" "${path}"
  fi
}

parse_workspace_arg() {
  WORKSPACE=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        [[ $# -ge 2 ]] || die "--workspace requires a value"
        WORKSPACE="$2"
        shift 2
        ;;
      -h|--help)
        return 1
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
  [[ -n "${WORKSPACE}" ]] || die "--workspace is required"
  WORKSPACE="$(absolute_path "${WORKSPACE}")"
  export WORKSPACE
}

validate_workspace() {
  local workspace="$1"
  [[ -d "${workspace}" ]] || die "workspace does not exist: ${workspace}"
  [[ -d "${workspace}/config" ]] || die "workspace missing config directory: ${workspace}"
  [[ -f "${workspace}/config/target.env" ]] || die "workspace missing config/target.env: ${workspace}"
}

ensure_workspace_dirs() {
  local workspace="$1"
  mkdir -p \
    "${workspace}/config" \
    "${workspace}/evidence/phase-0-preflight" \
    "${workspace}/evidence/phase-1-tls" \
    "${workspace}/evidence/phase-2-headers" \
    "${workspace}/evidence/phase-3-nikto" \
    "${workspace}/evidence/phase-4-nmap" \
    "${workspace}/evidence/phase-5-nuclei" \
    "${workspace}/evidence/phase-6-zap" \
    "${workspace}/evidence/phase-7-validation" \
    "${workspace}/evidence/phase-8-authenticated" \
    "${workspace}/logs" \
    "${workspace}/reports" \
    "${workspace}/status"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "${value}"
}
