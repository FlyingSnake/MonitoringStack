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
api_service_ip="$(kubectl -n default get service kubernetes -o jsonpath='{.spec.clusterIP}')"
api_endpoint_ip="$(kubectl -n default get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}')"
if [[ -z "${api_service_ip}" || -z "${api_endpoint_ip}" ]]; then
  echo "Kubernetes API Service 또는 endpoint IP를 확인할 수 없습니다." >&2
  exit 1
fi
api_server_cidrs="$(jq -cn --arg service "${api_service_ip}" --arg endpoint "${api_endpoint_ip}" '[($service + "/32"), ($endpoint + "/32")]')"
"${repo_root}/bootstrap/install-external-secrets-crds.sh"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 10.4.1 \
  --values "${repo_root}/bootstrap/argocd/values.yaml"

kubectl -n argocd rollout status deployment/argocd-server --timeout=5m

# install-gateway.sh의 초기 연결 확인용 echo Route는 Grafana의 HTTP→HTTPS
# redirect와 동일한 host/path를 사용한다. GitOps HTTPRoute보다 우선되지 않게
# App-of-Apps 적용 전에 제거한다.
kubectl -n envoy-gateway-system delete httproute gateway-echo --ignore-not-found >/dev/null

helm template monitoring-platform-local "${repo_root}/server/charts/platform-apps" \
  --values "${repo_root}/server/values/common.yaml" \
  --values "${repo_root}/server/env/dev/values.yaml" \
  --values "${runtime_dir}/server/values.yaml" \
  --set-json "applications.platform-foundation.values.apiServerCidrs=${api_server_cidrs}" \
  | kubectl apply --server-side --force-conflicts -f -

echo "Argo CD Applications are intentionally left in manual Sync mode:"
kubectl -n argocd get applications
echo "Run scripts/local/server/bootstrap-vault.sh after the Vault Application is synced, then sync applications by wave in the Argo CD UI."
