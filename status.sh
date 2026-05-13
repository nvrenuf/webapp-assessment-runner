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

if ! parse_workspace_arg "$@"; then
  usage
  exit 0
fi

validate_workspace "${WORKSPACE}"
print_status_summary "${WORKSPACE}"
