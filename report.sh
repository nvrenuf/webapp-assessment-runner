#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/findings.sh
source "${SCRIPT_DIR}/lib/findings.sh"

usage() {
  printf 'Usage: ./report.sh --workspace PATH\n'
}

if ! parse_workspace_arg "$@"; then
  usage
  exit 0
fi

validate_workspace "${WORKSPACE}"
write_empty_findings "${WORKSPACE}" >/dev/null
python3 "${SCRIPT_DIR}/tools/generate-report.py" --workspace "${WORKSPACE}"
