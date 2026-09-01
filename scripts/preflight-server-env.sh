#!/usr/bin/env bash
set -euo pipefail

environment="${1:?usage: scripts/preflight-server-env.sh <dev|stg|prd>}"
values_file="server/env/${environment}/values.yaml"

if [[ ! -f "${values_file}" ]]; then
  echo "Unknown server environment: ${environment}" >&2
  exit 2
fi

if rg --quiet 'REQUIRED_[A-Z0-9_]+' "${values_file}"; then
  echo "${environment} values still contain REQUIRED_* placeholders. Refusing deployment." >&2
  rg -n 'REQUIRED_[A-Z0-9_]+' "${values_file}" >&2
  exit 1
fi

echo "${environment} server values preflight passed."
