#!/usr/bin/env bash
set -euo pipefail

cluster_name="monitoring-local"
namespace="vault"
pod="vault-0"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
runtime_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"
state_dir="${runtime_dir}/server/.vault"
init_file="${state_dir}/init.json"
seed_marker="${state_dir}/seeded"

if ! kind get clusters | grep -qx "${cluster_name}"; then
  echo "kind cluster ${cluster_name} does not exist." >&2
  exit 1
fi

kubectl config use-context "kind-${cluster_name}" >/dev/null
for attempt in $(seq 1 120); do
  phase="$(kubectl -n "${namespace}" get "pod/${pod}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" == "Running" ]] && break
  sleep 5
done
if [[ "${phase}" != "Running" ]]; then
  echo "Vault pod did not reach Running state." >&2
  exit 1
fi
vault_status="$(kubectl -n "${namespace}" exec "${pod}" -- vault status -format=json 2>/dev/null || true)"
vault_initialized="$(printf '%s' "${vault_status}" | ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("initialized", false)' 2>/dev/null || printf false)"

# 로컬 Vault는 비영속 /tmp 저장소를 사용한다. Docker/Kind 재기동으로 서버
# 데이터가 사라졌다면, 이전 init 파일을 그대로 쓰지 않고 보존용 백업으로 옮긴다.
if [[ "${vault_initialized}" != "true" && -f "${init_file}" ]]; then
  backup_dir="${state_dir}-backup-$(date +%Y%m%d-%H%M%S)"
  mv "${state_dir}" "${backup_dir}"
  echo "Uninitialized Vault detected; preserved previous local state at ${backup_dir}."
fi

mkdir -p "${state_dir}"
chmod 700 "${state_dir}"

if [[ ! -f "${init_file}" ]]; then
  kubectl -n "${namespace}" exec "${pod}" -- vault operator init -format=json > "${init_file}"
  chmod 600 "${init_file}"
fi

root_token="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("root_token")' "${init_file}")"
ruby -rjson -e 'JSON.parse(File.read(ARGV[0])).fetch("unseal_keys_b64").each { |key| puts key }' "${init_file}" \
  | while IFS= read -r unseal_key; do
      kubectl -n "${namespace}" exec "${pod}" -- vault operator unseal "${unseal_key}" >/dev/null || true
    done

vault() {
  kubectl -n "${namespace}" exec -i "${pod}" -- env VAULT_TOKEN="${root_token}" vault "$@"
}

if ! kubectl -n external-secrets get serviceaccount external-secrets-vault >/dev/null 2>&1; then
  echo "Sync platform-secrets once so external-secrets-vault ServiceAccount exists, then rerun." >&2
  exit 1
fi

# The reviewer token must have system:auth-delegator, granted to the Vault
# ServiceAccount by the Helm chart. A manually managed ServiceAccount token
# Secret is used locally so a short-lived projected token does not make the
# Kind validation path fail after its default expiry.
reviewer_secret="vault-token-reviewer"
kubectl -n vault create secret generic "${reviewer_secret}" \
  --type=kubernetes.io/service-account-token \
  --dry-run=client -o yaml \
  | kubectl -n vault annotate --local -f - -o yaml \
      kubernetes.io/service-account.name=vault \
  | kubectl -n vault apply -f - >/dev/null
for attempt in $(seq 1 30); do
  reviewer_jwt="$(kubectl -n vault get secret "${reviewer_secret}" -o jsonpath='{.data.token}' 2>/dev/null || true)"
  [[ -n "${reviewer_jwt}" ]] && break
  sleep 1
done
if [[ -z "${reviewer_jwt:-}" ]]; then
  echo "Vault TokenReview ServiceAccount token was not populated." >&2
  exit 1
fi
reviewer_jwt="$(printf '%s' "${reviewer_jwt}" | base64 -d)"
cluster_ca="$(kubectl -n vault get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')"
vault auth enable kubernetes >/dev/null 2>&1 || true
vault write auth/kubernetes/config \
  token_reviewer_jwt="${reviewer_jwt}" \
  kubernetes_host="https://kubernetes.default.svc" \
  kubernetes_ca_cert="${cluster_ca}" >/dev/null
vault policy write monitoring-stack - <<'POLICY'
path "monitoring/data/*" { capabilities = ["read"] }
POLICY
vault write auth/kubernetes/role/monitoring-stack \
  bound_service_account_names=external-secrets-vault \
  bound_service_account_namespaces=external-secrets \
  policies=monitoring-stack \
  ttl=1h >/dev/null

vault policy write cert-manager-issuer - <<'POLICY'
path "pki_int/sign/monitoring-server" { capabilities = ["update"] }
POLICY
vault write auth/kubernetes/role/cert-manager-issuer \
  bound_service_account_names=cert-manager-vault-issuer \
  bound_service_account_namespaces=envoy-gateway-system \
  policies=cert-manager-issuer \
  ttl=1h >/dev/null

if kubectl -n awx get serviceaccount monitoring-awx >/dev/null 2>&1; then
  vault policy write awx-agent - <<'POLICY'
path "monitoring/data/ingestion" { capabilities = ["read"] }
path "pki_int/issue/monitoring-client" { capabilities = ["update"] }
POLICY
  vault write auth/kubernetes/role/awx-agent \
    bound_service_account_names=monitoring-awx \
    bound_service_account_namespaces=awx \
    policies=awx-agent \
    ttl=1h >/dev/null
else
  echo "AWX ServiceAccount가 아직 없어 awx-agent Vault role 설정을 건너뜁니다."
fi

if vault read pki_int/cert/ca >/dev/null 2>&1; then
  vault write pki_int/roles/monitoring-client \
    allow_any_name=true \
    max_ttl=168h >/dev/null
fi

if [[ -f "${seed_marker}" ]]; then
  echo "Vault 초기 seed는 이미 존재하며, Kubernetes Auth role을 갱신했습니다. State: ${state_dir}"
  exit 0
fi

vault secrets enable -path=monitoring -version=2 kv >/dev/null 2>&1 || true
vault secrets enable pki >/dev/null 2>&1 || true
vault secrets tune -max-lease-ttl=8760h pki
vault write -field=certificate pki/root/generate/internal common_name=monitoring-local-root ttl=8760h >/dev/null
vault secrets enable -path=pki_int pki >/dev/null 2>&1 || true
vault secrets tune -max-lease-ttl=4380h pki_int
intermediate_csr="$(vault write -field=csr pki_int/intermediate/generate/internal common_name=monitoring-local-intermediate)"
signed_intermediate="$(vault write -field=certificate pki/root/sign-intermediate csr="${intermediate_csr}" format=pem_bundle ttl=4380h)"
vault write pki_int/intermediate/set-signed certificate="${signed_intermediate}" >/dev/null
vault write pki_int/roles/monitoring-server \
  allowed_domains=localhost \
  allow_subdomains=true \
  allow_bare_domains=true \
  max_ttl=720h >/dev/null
vault write pki_int/roles/monitoring-client \
  allow_any_name=true \
  max_ttl=168h >/dev/null

random_secret() { openssl rand -base64 36 | tr -d '\n'; }

# Vault가 비영속 상태로 재초기화돼도 이미 실행 중인 stateful 서비스의 DB와
# 사용자 비밀번호가 바뀌면 안 된다. ExternalSecret target Secret은 Vault보다
# 오래 남아 있으므로, 값이 있으면 새 Vault에 복원하고 첫 설치에서만 생성한다.
existing_secret_value() {
  local secret_namespace="$1"
  local secret_name="$2"
  local secret_key="$3"
  local encoded

  encoded="$(kubectl -n "${secret_namespace}" get secret "${secret_name}" -o json 2>/dev/null \
    | jq -r --arg key "${secret_key}" '.data[$key] // empty' 2>/dev/null)" || return 1
  [[ -n "${encoded}" ]] || return 1
  printf '%s' "${encoded}" | base64 -d 2>/dev/null
}

secret_or_random() {
  local secret_namespace="$1"
  local secret_name="$2"
  local secret_key="$3"
  local value

  if value="$(existing_secret_value "${secret_namespace}" "${secret_name}" "${secret_key}")" && [[ -n "${value}" ]]; then
    echo "Preserving ${secret_namespace}/${secret_name}:${secret_key} in the reinitialized Vault." >&2
    printf '%s' "${value}"
  else
    random_secret
  fi
}

secret_or_default() {
  local secret_namespace="$1"
  local secret_name="$2"
  local secret_key="$3"
  local default_value="$4"
  local value

  if value="$(existing_secret_value "${secret_namespace}" "${secret_name}" "${secret_key}")" && [[ -n "${value}" ]]; then
    echo "Preserving ${secret_namespace}/${secret_name}:${secret_key} in the reinitialized Vault." >&2
    printf '%s' "${value}"
  else
    printf '%s' "${default_value}"
  fi
}

keycloak_admin="$(secret_or_random keycloak keycloak-admin admin-password)"
keycloak_database="$(secret_or_random keycloak keycloak-postgresql password)"
minio_user="$(secret_or_default minio minio-root root-user monitoring)"
minio_password="$(secret_or_random minio minio-root root-password)"
awx_admin="$(secret_or_random awx awx-admin password)"
argocd_client_secret="$(secret_or_random keycloak oidc-client-secrets argocd-client-secret)"
grafana_client_secret="$(secret_or_random keycloak oidc-client-secrets grafana-client-secret)"
awx_client_secret="$(secret_or_random keycloak oidc-client-secrets awx-client-secret)"
ingestion_username="$(secret_or_default alloy alloy-ingest-client INGEST_USERNAME alloy)"
ingestion_password="$(secret_or_random alloy alloy-ingest-client INGEST_PASSWORD)"
# Envoy Gateway BasicAuth는 Apache htpasswd의 {SHA} 형식만 지원한다.
# 이 값은 로컬 Vault에만 저장하며 Git에는 평문 자격증명을 남기지 않는다.
ingestion_password_sha1="$(printf '%s' "${ingestion_password}" | openssl dgst -sha1 -binary | base64)"
htpasswd_entry="alloy:{SHA}${ingestion_password_sha1}"

vault kv put monitoring/keycloak admin-password="${keycloak_admin}" >/dev/null
vault kv put monitoring/keycloak-postgresql password="${keycloak_database}" >/dev/null
vault kv put monitoring/minio root-user="${minio_user}" root-password="${minio_password}" >/dev/null
vault kv put monitoring/object-storage access-key-id="${minio_user}" secret-access-key="${minio_password}" >/dev/null
vault kv put monitoring/awx admin-password="${awx_admin}" >/dev/null
vault kv put monitoring/oidc \
  argocd-client-secret="${argocd_client_secret}" \
  grafana-client-secret="${grafana_client_secret}" \
  awx-client-secret="${awx_client_secret}" >/dev/null
vault kv put monitoring/ingestion \
  htpasswd="${htpasswd_entry}" \
  username="${ingestion_username}" \
  password="${ingestion_password}" >/dev/null
vault kv put monitoring/pki ingest-ca-crt="$(vault read -field=certificate pki_int/cert/ca)" >/dev/null

vault write -format=json pki_int/issue/monitoring-client common_name=local-alloy ttl=24h > "${state_dir}/alloy-client.json"
ruby -rjson -e '
  data = JSON.parse(File.read(ARGV[0])).fetch("data")
  File.write(ARGV[1], data.fetch("certificate"))
  File.write(ARGV[2], data.fetch("private_key"))
  File.write(ARGV[3], data.fetch("issuing_ca"))
' "${state_dir}/alloy-client.json" "${state_dir}/alloy-client.crt" "${state_dir}/alloy-client.key" "${state_dir}/ca.crt"
chmod 600 "${state_dir}/alloy-client.key" "${state_dir}/init.json"
touch "${seed_marker}"

echo "Vault bootstrap completed. Local client certificate and ingestion credentials are in ${state_dir}."
