#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  printf 'Usage: ./assess.sh --workspace PATH [--skip-preflight]\n'
}

WORKSPACE=""
SKIP_PREFLIGHT="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      [[ $# -ge 2 ]] || die "--workspace requires a value"
      WORKSPACE="$2"
      shift 2
      ;;
    --skip-preflight)
      SKIP_PREFLIGHT="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "${WORKSPACE}" ]]; then
  usage
  die "--workspace is required"
fi
WORKSPACE="$(absolute_path "${WORKSPACE}")"
export WORKSPACE

validate_workspace "${WORKSPACE}"

phases=(
  "01-tls.sh"
  "02-headers.sh"
  "03-nikto.sh"
  "04-nmap.sh"
  "05-nuclei.sh"
  "06-zap-passive.sh"
  "07-validation.sh"
  "08-authenticated-placeholder.sh"
)

if [[ "${SKIP_PREFLIGHT}" == "true" ]]; then
  printf 'warning: skipping preflight; dependency, package, scope, and connectivity checks were not run\n' >&2
else
  "${SCRIPT_DIR}/phases/00-preflight.sh" --workspace "${WORKSPACE}" --yes
fi

for phase in "${phases[@]}"; do
  "${SCRIPT_DIR}/phases/${phase}" --workspace "${WORKSPACE}"
done

printf 'Assessment stub run complete for workspace: %s\n' "${WORKSPACE}"
