#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
state_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}/server/.vault"

if [[ ! -f "${state_dir}/ca.crt" || ! -f "${state_dir}/alloy-client.crt" || ! -f "${state_dir}/alloy-client.key" || ! -f "${state_dir}/init.json" ]]; then
  echo "Local Vault TLS materials are unavailable. Run scripts/local/server/bootstrap-vault.sh after syncing Vault." >&2
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

for host in grafana.ui.localhost keycloak.ui.localhost argocd.ui.localhost awx.ui.localhost; do
  location="$(curl --silent --show-error --head --max-time 15 --resolve "${host}:80:127.0.0.1" "http://${host}/" | awk 'tolower($1) == "location:" { print $2 }' | tr -d '\r')"
  [[ "${location}" == "https://${host}/" ]] || { echo "HTTP redirect is invalid for ${host}: ${location}" >&2; exit 1; }
done

expect_status 200 https://grafana.ui.localhost/api/health --cacert "${state_dir}/ca.crt"
expect_status 200 https://keycloak.ui.localhost/realms/monitoring/.well-known/openid-configuration --cacert "${state_dir}/ca.crt"
expect_status 200 https://awx.ui.localhost/api/v2/ping/ --cacert "${state_dir}/ca.crt"
expect_status 307 https://argocd.ui.localhost/api/version --cacert "${state_dir}/ca.crt" --max-redirs 0

for endpoint in \
  'loki.ingest.localhost /loki/api/v1/labels' \
  'mimir.ingest.localhost /prometheus/api/v1/status/buildinfo' \
  'tempo.ingest.localhost /ready' \
  'pyroscope.ingest.localhost /ready'; do
  read -r host path <<<"${endpoint}"
  if [[ "${host}" == "tempo.ingest.localhost" ]]; then
    # The distributor exposes OTLP/HTTP only; an empty JSON request is accepted
    # and proves that the authenticated request reached the OTLP receiver.
    path="/v1/traces"
    expect_status 200 "https://${host}${path}" --cacert "${state_dir}/ca.crt" --cert "${state_dir}/alloy-client.crt" --key "${state_dir}/alloy-client.key" --user "alloy:${ingestion_password}" -X POST -H 'Content-Type: application/json' --data '{}'
    expect_status 401 "https://${host}${path}" --cacert "${state_dir}/ca.crt" --cert "${state_dir}/alloy-client.crt" --key "${state_dir}/alloy-client.key" -X POST -H 'Content-Type: application/json' --data '{}'
    unauthenticated=(curl --silent --output /dev/null --max-time 15 --cacert "${state_dir}/ca.crt" --user "alloy:${ingestion_password}" -X POST -H 'Content-Type: application/json' --data '{}')
  else
    expect_status 200 "https://${host}${path}" --cacert "${state_dir}/ca.crt" --cert "${state_dir}/alloy-client.crt" --key "${state_dir}/alloy-client.key" --user "alloy:${ingestion_password}"
    expect_status 401 "https://${host}${path}" --cacert "${state_dir}/ca.crt" --cert "${state_dir}/alloy-client.crt" --key "${state_dir}/alloy-client.key"
    unauthenticated=(curl --silent --output /dev/null --max-time 15 --cacert "${state_dir}/ca.crt" --user "alloy:${ingestion_password}")
  fi
  if "${unauthenticated[@]}" "https://${host}${path}"; then
    echo "mTLS was not enforced for ${host}" >&2
    exit 1
  fi
done

echo "UI HTTPS redirects, UI APIs, and ingest mTLS + Basic Auth contracts passed."
