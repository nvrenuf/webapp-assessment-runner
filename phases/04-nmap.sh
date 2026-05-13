#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"
source "${REPO_ROOT}/lib/evidence.sh"
source "${REPO_ROOT}/lib/status.sh"

parse_workspace_arg "$@" || { printf 'Usage: %s --workspace PATH\n' "$0"; exit 0; }
validate_workspace "${WORKSPACE}"
write_phase_note "${WORKSPACE}" "phase-4-nmap" "Nmap stub completed. No port scanning was performed."
write_status "${WORKSPACE}" "phase-4-nmap" "completed" "Stub completed without port scanning."
printf 'phase-4-nmap completed\n'
