#!/usr/bin/env bash
set -euo pipefail

environment="${ENVIRONMENT:?ENVIRONMENT must be dev, stg, or prd}"
case "${environment}" in
  dev|stg|prd) ;;
  *) echo "ENVIRONMENT must be dev, stg, or prd" >&2; exit 1 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helm_args=(
  upgrade --install argocd argo/argo-cd
  --namespace argocd
  --create-namespace
  --version 10.4.1
  --values "${repo_root}/bootstrap/argocd/values.yaml"
)

if [[ "${1:-}" == "--enable-oidc" ]]; then
  helm_args+=(--values "${repo_root}/bootstrap/argocd/oidc/${environment}.yaml")
fi

helm "${helm_args[@]}"
