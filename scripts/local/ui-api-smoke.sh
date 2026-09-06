#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
state_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}/server/.vault"

if [[ ! -f "${state_dir}/init.json" ]]; then
  echo "Local Vault bootstrap 자료가 없습니다. Vault Sync 후 scripts/local/server/bootstrap-vault.sh를 실행하세요." >&2
  exit 1
fi

root_token="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("root_token")' "${state_dir}/init.json")"
ingestion_password="$(kubectl -n vault exec vault-0 -- env VAULT_TOKEN="${root_token}" vault kv get -field=password monitoring/ingestion)"

expect_status() {
  local expected="$1"
  local url="$2"
  shift 2
  local actual
  actual="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 15 "$@" "${url}")"
  [[ "${actual}" == "${expected}" ]] || { echo "Expected ${expected}, got ${actual}: ${url}" >&2; exit 1; }
}

for host in grafana.demo.flyingsnake.xyz keycloak.demo.flyingsnake.xyz argocd.demo.flyingsnake.xyz awx.demo.flyingsnake.xyz; do
  location="$(curl --silent --show-error --head --max-time 15 --resolve "${host}:80:127.0.0.1" "http://${host}/" | awk 'tolower($1) == "location:" { print $2 }' | tr -d '\r')"
  [[ "${location}" == "https://${host}/" ]] || { echo "HTTP redirect is invalid for ${host}: ${location}" >&2; exit 1; }
done

expect_status 200 https://grafana.demo.flyingsnake.xyz/api/health --resolve grafana.demo.flyingsnake.xyz:443:127.0.0.1
expect_status 200 https://keycloak.demo.flyingsnake.xyz/realms/monitoring/.well-known/openid-configuration --resolve keycloak.demo.flyingsnake.xyz:443:127.0.0.1
expect_status 200 https://awx.demo.flyingsnake.xyz/api/v2/ping/ --resolve awx.demo.flyingsnake.xyz:443:127.0.0.1
expect_status 307 https://argocd.demo.flyingsnake.xyz/api/version --resolve argocd.demo.flyingsnake.xyz:443:127.0.0.1 --max-redirs 0

for endpoint in \
  'loki-ingest.demo.flyingsnake.xyz /loki/api/v1/labels' \
  'mimir-ingest.demo.flyingsnake.xyz /prometheus/api/v1/status/buildinfo' \
  'tempo-ingest.demo.flyingsnake.xyz /ready' \
  'pyroscope-ingest.demo.flyingsnake.xyz /ready'; do
  read -r host path <<<"${endpoint}"
  if [[ "${host}" == "tempo-ingest.demo.flyingsnake.xyz" ]]; then
    # The distributor exposes OTLP/HTTP only; an empty JSON request is accepted
    # and proves that the authenticated request reached the OTLP receiver.
    path="/v1/traces"
    expect_status 200 "https://${host}${path}" --resolve "${host}:443:127.0.0.1" --user "alloy:${ingestion_password}" -X POST -H 'Content-Type: application/json' --data '{}'
    expect_status 401 "https://${host}${path}" --resolve "${host}:443:127.0.0.1" -X POST -H 'Content-Type: application/json' --data '{}'
  else
    expect_status 200 "https://${host}${path}" --resolve "${host}:443:127.0.0.1" --user "alloy:${ingestion_password}"
    expect_status 401 "https://${host}${path}" --resolve "${host}:443:127.0.0.1"
  fi
done

echo "UI HTTPS redirects, UI APIs, and ingest Basic Auth contracts passed."
