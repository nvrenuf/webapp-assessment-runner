#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh --check-only|--install-deps

Modes:
  --check-only    Report missing dependencies without modifying the system.
  --install-deps  Install missing apt packages where possible.

Safety:
  This script never runs apt update, apt upgrade, or apt full-upgrade.
EOF
}

MODE="check-only"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      MODE="check-only"
      shift
      ;;
    --install-deps)
      MODE="install-deps"
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

required_tools=(bash curl openssl nmap nikto nuclei jq python3)
required_packages=(bash curl openssl nmap nikto nuclei jq python3)

flex_names=(testssl zap)
flex_candidates=("testssl testssl.sh" "zaproxy /usr/share/zaproxy/zap.sh owasp-zap")
flex_packages=(testssl.sh zaproxy)

missing_required=()
missing_flexible=()
packages_to_install=()

tool_exists() {
  local candidate
  for candidate in "$@"; do
    if [[ "${candidate}" = /* && -x "${candidate}" ]]; then
      return 0
    fi
    if [[ "${candidate}" != /* ]] && command -v "${candidate}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

add_package_once() {
  local package_name="$1"
  local existing
  for existing in "${packages_to_install[@]}"; do
    [[ "${existing}" == "${package_name}" ]] && return 0
  done
  packages_to_install+=("${package_name}")
}

check_dependencies() {
  missing_required=()
  missing_flexible=()
  packages_to_install=()

  local index tool package_name name candidates
  info "Checking required tools..."
  for index in "${!required_tools[@]}"; do
    tool="${required_tools[$index]}"
    package_name="${required_packages[$index]}"
    if tool_exists "${tool}"; then
      info "ok: ${tool}"
    else
      info "missing: ${tool} (apt package: ${package_name})"
      missing_required+=("${tool}")
      add_package_once "${package_name}"
    fi
  done

  info "Checking flexible tools..."
  for index in "${!flex_names[@]}"; do
    name="${flex_names[$index]}"
    package_name="${flex_packages[$index]}"
    IFS=' ' read -r -a candidates <<< "${flex_candidates[$index]}"
    if tool_exists "${candidates[@]}"; then
      info "ok: ${name}"
    else
      info "missing: ${name} (accepted: ${flex_candidates[$index]}; apt package: ${package_name})"
      missing_flexible+=("${name}")
      add_package_once "${package_name}"
    fi
  done
}

check_dependencies

if [[ "${MODE}" == "check-only" ]]; then
  if [[ "${#missing_required[@]}" -gt 0 || "${#missing_flexible[@]}" -gt 0 ]]; then
    info "Dependency check failed. Missing required: ${missing_required[*]:-none}. Missing flexible groups: ${missing_flexible[*]:-none}."
    info "No packages were installed. Run sudo ./install.sh --install-deps to install missing apt packages where available."
    exit 1
  fi
  info "Dependency check complete. No packages were installed."
  exit 0
fi

if [[ "${MODE}" == "install-deps" ]]; then
  [[ "${EUID}" -eq 0 ]] || die "--install-deps must be run as root"
  command -v apt-get >/dev/null 2>&1 || die "apt-get not found; --install-deps requires Kali/Debian with apt-get"

  if [[ "${#packages_to_install[@]}" -gt 0 ]]; then
    info "Installing missing apt packages: ${packages_to_install[*]}"
    apt-get install -y "${packages_to_install[@]}"
  else
    info "No missing apt packages detected."
  fi

  check_dependencies
  if [[ "${#missing_required[@]}" -gt 0 || "${#missing_flexible[@]}" -gt 0 ]]; then
    die "dependency installation incomplete. Missing required: ${missing_required[*]:-none}. Missing flexible groups: ${missing_flexible[*]:-none}."
  fi
  info "Dependency installation check complete."
fi
