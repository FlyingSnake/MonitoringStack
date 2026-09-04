#!/usr/bin/env bash
set -euo pipefail

cluster_name="monitoring-local"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
runtime_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"

if [[ ! -f "${runtime_dir}/server/values.yaml" ]]; then
  echo "Local values are unavailable: ${runtime_dir}/server/values.yaml" >&2
  exit 1
fi

kubectl config use-context "kind-${cluster_name}"
"${repo_root}/bootstrap/install-external-secrets-crds.sh"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 10.4.1 \
  --values "${repo_root}/bootstrap/argocd/values.yaml"

kubectl -n argocd rollout status deployment/argocd-server --timeout=5m

helm template monitoring-platform-local "${repo_root}/server/charts/platform-apps" \
  --values "${repo_root}/server/values/common.yaml" \
  --values "${repo_root}/server/env/dev/values.yaml" \
  --values "${runtime_dir}/server/values.yaml" \
  | kubectl apply --server-side --force-conflicts -f -

echo "Argo CD Applications are intentionally left in manual Sync mode:"
kubectl -n argocd get applications
echo "Run scripts/local/server/bootstrap-vault.sh after the Vault Application is synced, then sync applications by wave in the Argo CD UI."
