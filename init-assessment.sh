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

case "${AUTH}" in
  none|placeholder) ;;
  *) die "--auth must be one of: none, placeholder" ;;
esac

if [[ -z "${COMPANY_SLUG}" ]]; then
  COMPANY_SLUG="$(slugify "${COMPANY}")"
else
  COMPANY_SLUG="$(slugify "${COMPANY_SLUG}")"
fi

TARGET_SLUG="$(slugify "${TARGET}")"
RUN_ID="$(utc_run_id)"
WORKSPACE="$(absolute_path "${OUTPUT_ROOT}")/${COMPANY_SLUG}/${TARGET_SLUG}/${RUN_ID}"

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

sed \
  -e "s|{{COMPANY}}|$(json_escape "${COMPANY}")|g" \
  -e "s|{{COMPANY_SLUG}}|$(json_escape "${COMPANY_SLUG}")|g" \
  -e "s|{{ENGAGEMENT}}|$(json_escape "${ENGAGEMENT}")|g" \
  -e "s|{{TARGET}}|$(json_escape "${TARGET}")|g" \
  -e "s|{{LOGIN_PATH}}|$(json_escape "${LOGIN_PATH}")|g" \
  -e "s|{{ENVIRONMENT}}|$(json_escape "${ENVIRONMENT}")|g" \
  -e "s|{{PROFILE}}|$(json_escape "${PROFILE}")|g" \
  -e "s|{{AUTH}}|$(json_escape "${AUTH}")|g" \
  -e "s|{{TESTER}}|$(json_escape "${TESTER}")|g" \
  "${SCRIPT_DIR}/templates/target.env.tmpl" > "${TARGET_ENV}"

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
  "company_slug": "$(json_escape "${COMPANY_SLUG}")",
  "engagement": "$(json_escape "${ENGAGEMENT}")",
  "target": "$(json_escape "${TARGET}")",
  "target_slug": "$(json_escape "${TARGET_SLUG}")",
  "login_path": "$(json_escape "${LOGIN_PATH}")",
  "environment": "$(json_escape "${ENVIRONMENT}")",
  "profile": "$(json_escape "${PROFILE}")",
  "auth": "$(json_escape "${AUTH}")",
  "tester": "$(json_escape "${TESTER}")",
  "run_id": "$(json_escape "${RUN_ID}")",
  "workspace": "$(json_escape "${WORKSPACE}")",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
EOF

printf '%s\n' "${WORKSPACE}"
