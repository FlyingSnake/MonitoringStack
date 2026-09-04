#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib.sh"

require_kind_cluster monitoring-local

if ! docker ps --format '{{.Names}}' | grep -qx monitoring-local-git; then
  echo "Local Git daemon is not running. Run scripts/local/git-server/start.sh." >&2
  exit 1
fi

kubectl -n argocd get applications >/dev/null
unhealthy="$(kubectl -n argocd get applications -o json | jq -r '.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy") | "\(.metadata.name): \(.status.sync.status // "Unknown")/\(.status.health.status // "Unknown")"')"
if [[ -n "${unhealthy}" ]]; then
  echo "Argo CD Applications are not ready:" >&2
  printf '%s\n' "${unhealthy}" >&2
  exit 1
fi

kubectl -n envoy-gateway-system wait --for=condition=Ready certificate/monitoring-ui-tls certificate/monitoring-ingest-tls --timeout=10s >/dev/null
route_errors="$(kubectl get httproute -A -o json | jq -r '.items[] | select(any(.status.parents[]?.conditions[]?; .type == "Accepted" and .status != "True")) | "\(.metadata.namespace)/\(.metadata.name)"')"
if [[ -n "${route_errors}" ]]; then
  echo "Gateway HTTPRoute acceptance failed:" >&2
  printf '%s\n' "${route_errors}" >&2
  exit 1
fi

echo "Docker, Kind, local Git daemon, Argo CD Applications, Gateway certificates, and HTTPRoutes are ready."
