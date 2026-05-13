#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: ./init-assessment.sh --company NAME --engagement NAME --target URL [options]

Options:
  --company NAME
  --company-slug SLUG
  --engagement NAME
  --target URL
  --login-path PATH
  --environment NAME
  --profile safe|balanced|deep|maintenance
  --auth none|placeholder
      Aliases for none: no, false, off, unauthenticated
      Aliases for placeholder: yes, true, on, authenticated, auth
  --tester NAME
  --output-root PATH
  --yes
  -h, --help
EOF
}

COMPANY=""
COMPANY_SLUG=""
ENGAGEMENT=""
TARGET=""
LOGIN_PATH=""
ENVIRONMENT="unspecified"
PROFILE="safe"
AUTH="none"
AUTH_MODE="none"
AUTH_ENABLED="false"
TESTER=""
OUTPUT_ROOT="assessments"
YES="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --company) COMPANY="${2:-}"; shift 2 ;;
    --company-slug) COMPANY_SLUG="${2:-}"; shift 2 ;;
    --engagement) ENGAGEMENT="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --login-path) LOGIN_PATH="${2:-}"; shift 2 ;;
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --auth) AUTH="${2:-}"; shift 2 ;;
    --tester) TESTER="${2:-}"; shift 2 ;;
    --output-root) OUTPUT_ROOT="${2:-}"; shift 2 ;;
    --yes) YES="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "${COMPANY}" ]] || die "--company is required"
[[ -n "${ENGAGEMENT}" ]] || die "--engagement is required"
[[ -n "${TARGET}" ]] || die "--target is required"

case "${PROFILE}" in
  safe|balanced|deep|maintenance) ;;
  *) die "--profile must be one of: safe, balanced, deep, maintenance" ;;
esac

normalize_auth() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${value}" in
    none|no|false|off|unauthenticated)
      AUTH_MODE="none"
      AUTH_ENABLED="false"
      ;;
    placeholder|yes|true|on|authenticated|auth)
      AUTH_MODE="placeholder"
      AUTH_ENABLED="true"
      ;;
    *)
      die "--auth must be one of: none, placeholder, or an accepted alias"
      ;;
  esac
}

normalize_auth "${AUTH}"

if [[ -z "${COMPANY_SLUG}" ]]; then
  COMPANY_SLUG="$(slugify "${COMPANY}")"
else
  COMPANY_SLUG="$(slugify "${COMPANY_SLUG}")"
fi

TARGET_SLUG="$(slugify "${TARGET}")"
RUN_ID="$(utc_run_id)"
OUTPUT_ROOT="${OUTPUT_ROOT%/}"
WORKSPACE="${OUTPUT_ROOT}/${COMPANY_SLUG}/${TARGET_SLUG}/${RUN_ID}"
TARGET_BASE_URL="${TARGET%/}"
TARGET_HOST="$(printf '%s' "${TARGET_BASE_URL}" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#/.*$##; s#@##; s#:[0-9]+$##')"
if [[ -z "${LOGIN_PATH}" ]]; then
  LOGIN_PATH="/"
fi
if [[ "${LOGIN_PATH}" != /* ]]; then
  LOGIN_PATH="/${LOGIN_PATH}"
fi
LOGIN_URL="${TARGET_BASE_URL}${LOGIN_PATH}"

if [[ "${YES}" != "true" ]]; then
  info "Workspace to create: ${WORKSPACE}"
  read -r -p "Create assessment workspace? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || die "aborted"
fi

ensure_workspace_dirs "${WORKSPACE}"

TARGET_ENV="${WORKSPACE}/config/target.env"
SCOPE_YAML="${WORKSPACE}/config/scope.yaml"
AUTH_ENV="${WORKSPACE}/config/auth.env"
METADATA_JSON="${WORKSPACE}/config/metadata.json"

cat > "${TARGET_ENV}" <<EOF
# Generated assessment target configuration.
# Keep this file inside the workspace. Do not commit generated configs.
COMPANY_NAME="$(env_double_quote_escape "${COMPANY}")"
COMPANY_SLUG="$(env_double_quote_escape "${COMPANY_SLUG}")"
ENGAGEMENT_NAME="$(env_double_quote_escape "${ENGAGEMENT}")"
TARGET_BASE_URL="$(env_double_quote_escape "${TARGET_BASE_URL}")"
TARGET_HOST="$(env_double_quote_escape "${TARGET_HOST}")"
LOGIN_PATH="$(env_double_quote_escape "${LOGIN_PATH}")"
LOGIN_URL="$(env_double_quote_escape "${LOGIN_URL}")"
ENVIRONMENT="$(env_double_quote_escape "${ENVIRONMENT}")"
PROFILE="$(env_double_quote_escape "${PROFILE}")"
AUTH_MODE="$(env_double_quote_escape "${AUTH_MODE}")"
AUTH_ENABLED="$(env_double_quote_escape "${AUTH_ENABLED}")"
TESTER="$(env_double_quote_escape "${TESTER}")"
RUN_ID="$(env_double_quote_escape "${RUN_ID}")"
WORKSPACE="$(env_double_quote_escape "${WORKSPACE}")"
EOF

sed \
  -e "s|{{TARGET}}|$(json_escape "${TARGET}")|g" \
  -e "s|{{LOGIN_PATH}}|$(json_escape "${LOGIN_PATH}")|g" \
  -e "s|{{ENVIRONMENT}}|$(json_escape "${ENVIRONMENT}")|g" \
  "${SCRIPT_DIR}/templates/scope.yaml.tmpl" > "${SCOPE_YAML}"

cp "${SCRIPT_DIR}/templates/auth.env.example" "${AUTH_ENV}"
chmod 0600 "${AUTH_ENV}"

cat > "${METADATA_JSON}" <<EOF
{
  "company": "$(json_escape "${COMPANY}")",
  "company_name": "$(json_escape "${COMPANY}")",
  "company_slug": "$(json_escape "${COMPANY_SLUG}")",
  "engagement": "$(json_escape "${ENGAGEMENT}")",
  "engagement_name": "$(json_escape "${ENGAGEMENT}")",
  "target": "$(json_escape "${TARGET_BASE_URL}")",
  "target_base_url": "$(json_escape "${TARGET_BASE_URL}")",
  "target_host": "$(json_escape "${TARGET_HOST}")",
  "target_slug": "$(json_escape "${TARGET_SLUG}")",
  "login_path": "$(json_escape "${LOGIN_PATH}")",
  "login_url": "$(json_escape "${LOGIN_URL}")",
  "environment": "$(json_escape "${ENVIRONMENT}")",
  "profile": "$(json_escape "${PROFILE}")",
  "auth_mode": "$(json_escape "${AUTH_MODE}")",
  "auth_enabled": ${AUTH_ENABLED},
  "tester": "$(json_escape "${TESTER}")",
  "run_id": "$(json_escape "${RUN_ID}")",
  "workspace": "$(json_escape "${WORKSPACE}")",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF

printf '%s\n' "${WORKSPACE}"
