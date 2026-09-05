#!/usr/bin/env bash
set -euo pipefail

cluster_name="monitoring-local"
namespace="envoy-gateway-system"
release_name="envoy-gateway"
chart_version="v1.9.0"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
runtime_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"
certificate_name="${MONITORING_LOCAL_LE_CERT_NAME:-demo.flyingsnake.xyz}"
certificate_dir="${MONITORING_LOCAL_LE_CERT_DIR:-${runtime_dir}/letsencrypt/config/live/${certificate_name}}"
context="kind-${cluster_name}"

if ! kind get clusters | grep -qx "${cluster_name}"; then
  echo "kind cluster ${cluster_name} does not exist. Run create-cluster.sh first." >&2
  exit 1
fi

kubectl config use-context "${context}" >/dev/null

helm upgrade --install "${release_name}" \
  oci://docker.io/envoyproxy/gateway-helm \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  --create-namespace \
  --wait \
  --timeout 10m

kubectl -n "${namespace}" rollout status deployment/envoy-gateway --timeout=5m

fullchain="${certificate_dir}/fullchain.pem"
private_key="${certificate_dir}/privkey.pem"
if [[ ! -r "${fullchain}" || ! -r "${private_key}" ]]; then
  echo "Let's Encrypt certificate files are unavailable: ${certificate_dir}" >&2
  echo "Set MONITORING_LOCAL_LE_CERT_DIR or place fullchain.pem and privkey.pem under local/letsencrypt/config/live/${certificate_name}." >&2
  exit 1
fi

create_letsencrypt_tls_secret() {
  local secret_name="$1"
  kubectl -n "${namespace}" create secret tls "${secret_name}" \
    --cert="${fullchain}" \
    --key="${private_key}" \
    --dry-run=client -o yaml | kubectl apply -f -
}
# 이전 Vault/cert-manager Certificate가 남아 있으면 외부 인증서 Secret을 다시
# 덮어쓸 수 있다. cert-manager가 아직 설치되지 않은 최초 Gateway 설치도 허용한다.
if kubectl api-resources --api-group=cert-manager.io -o name 2>/dev/null | grep -qx certificates.cert-manager.io; then
  kubectl -n "${namespace}" delete certificate monitoring-ui-tls monitoring-ingest-tls --ignore-not-found
fi
create_letsencrypt_tls_secret monitoring-ui-tls
create_letsencrypt_tls_secret monitoring-ingest-tls

kubectl apply -f "${script_dir}/envoy-gateway.yaml"
kubectl apply -f "${script_dir}/gateway-smoke-test.yaml"
kubectl -n "${namespace}" rollout status deployment/gateway-echo --timeout=5m

for attempt in $(seq 1 60); do
  service_name="$(kubectl -n "${namespace}" get service \
    -l gateway.envoyproxy.io/owning-gateway-namespace="${namespace}",gateway.envoyproxy.io/owning-gateway-name=monitoring-local \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "${service_name}" ]] && break
  sleep 2
done
if [[ -z "${service_name}" ]]; then
  echo "Managed Envoy Service was not created." >&2
  exit 1
fi

node_ports="$(kubectl -n "${namespace}" get service "${service_name}" -o jsonpath='{range .spec.ports[*]}{.name}:{.nodePort}{" "}{end}')"
echo "Gateway Service: ${service_name} (${node_ports})"
if [[ "${node_ports}" != *"http:30080"* || "${node_ports}" != *"https:30443"* ]]; then
  echo "Unexpected NodePort assignment. Expected http:30080 and https:30443." >&2
  kubectl -n "${namespace}" get service "${service_name}" -o yaml >&2
  exit 1
fi

echo "Waiting for host port smoke tests..."
for attempt in $(seq 1 30); do
  if curl --fail --silent --show-error --max-time 5 -H 'Host: grafana.demo.flyingsnake.xyz' http://127.0.0.1/ >/dev/null && \
    curl --fail --silent --show-error --max-time 5 --resolve grafana.demo.flyingsnake.xyz:443:127.0.0.1 https://grafana.demo.flyingsnake.xyz/ >/dev/null; then
    echo "Envoy Gateway is reachable at host ports 80 and 443."
    exit 0
  fi
  sleep 2
done

echo "Gateway resources were created, but the host-port smoke test did not pass." >&2
kubectl -n "${namespace}" get gateway,httproute,service,pods >&2
exit 1
