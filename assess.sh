#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  printf 'Usage: ./assess.sh --workspace PATH\n'
}

if ! parse_workspace_arg "$@"; then
  usage
  exit 0
fi

validate_workspace "${WORKSPACE}"

phases=(
  "00-preflight.sh"
  "01-tls.sh"
  "02-headers.sh"
  "03-nikto.sh"
  "04-nmap.sh"
  "05-nuclei.sh"
  "06-zap-passive.sh"
  "07-validation.sh"
  "08-authenticated-placeholder.sh"
)

for phase in "${phases[@]}"; do
  "${SCRIPT_DIR}/phases/${phase}" --workspace "${WORKSPACE}"
done

printf 'Assessment stub run complete for workspace: %s\n' "${WORKSPACE}"
