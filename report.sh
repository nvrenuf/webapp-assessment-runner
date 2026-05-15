#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf 'Usage: ./report.sh --workspace PATH [--yes] [--clean] [--verbose] [--archive]\n'
}

args=()
if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      [[ $# -ge 2 ]] || { printf 'error: --workspace requires a value\n' >&2; exit 1; }
      args+=("$1" "$2")
      shift 2
      ;;
    --yes|--clean|--verbose|--archive)
      args+=("$1")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

exec "${SCRIPT_DIR}/phases/09-reporting.sh" "${args[@]}"
