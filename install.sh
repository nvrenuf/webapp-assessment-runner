#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

if [[ "${EUID}" -ne 0 ]]; then
  die "install.sh must be run as root so it can validate Kali package prerequisites"
fi

commands=(bash python3 sed date find)
optional_tools=(openssl curl nikto nmap nuclei zaproxy)

info "Checking required commands..."
for command_name in "${commands[@]}"; do
  require_command "${command_name}"
  info "ok: ${command_name}"
done

info "Checking optional assessment tools..."
missing=()
for tool in "${optional_tools[@]}"; do
  if command -v "${tool}" >/dev/null 2>&1; then
    info "ok: ${tool}"
  else
    missing+=("${tool}")
    info "missing: ${tool}"
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  info "Install missing tools through your approved Kali package process before enabling active phases."
fi

info "Install check complete. No packages were installed and no system upgrades were run."
