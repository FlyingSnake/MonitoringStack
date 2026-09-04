#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
state_dir="${repo_root}/local/server/.vault"

if [[ ! -f "${state_dir}/init.json" || ! -f "${state_dir}/alloy-client.crt" ]]; then
  echo "로컬 Vault 인증 자료가 없습니다. local/server/bootstrap-vault.sh를 먼저 실행하세요." >&2
  exit 1
fi

root_token="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("root_token")' "${state_dir}/init.json")"
ingestion_password="$(kubectl -n vault exec vault-0 -- env VAULT_TOKEN="${root_token}" vault kv get -field=password monitoring/ingestion)"

gateway_status() {
  local endpoint_host="$1"
  local endpoint_path="$2"
  local authentication="$3"
  local args=(--silent --output /dev/null --write-out '%{http_code}' --resolve "${endpoint_host}:443:127.0.0.1" --cacert "${state_dir}/ca.crt")
  if [[ "${authentication}" == "mtls" || "${authentication}" == "full" ]]; then
    args+=(--cert "${state_dir}/alloy-client.crt" --key "${state_dir}/alloy-client.key")
  fi
  if [[ "${authentication}" == "basic" || "${authentication}" == "full" ]]; then
    args+=(--user "alloy:${ingestion_password}")
  fi
  curl "${args[@]}" "https://${endpoint_host}${endpoint_path}"
}

gateway_query() {
  local endpoint_host="$1"
  local endpoint_path="$2"
  local result_file="$3"

  curl --silent --show-error --fail \
    --resolve "${endpoint_host}:443:127.0.0.1" \
    --cacert "${state_dir}/ca.crt" \
    --cert "${state_dir}/alloy-client.crt" \
    --key "${state_dir}/alloy-client.key" \
    --user "alloy:${ingestion_password}" \
    "https://${endpoint_host}${endpoint_path}" > "${result_file}"
}

work_dir="$(mktemp -d)"
cleanup() {
  [[ -n "${forward_pid:-}" ]] && kill "${forward_pid}" 2>/dev/null || true
  rm -rf "${work_dir}"
}
trap cleanup EXIT

loki_result="${work_dir}/loki.json"
mimir_result="${work_dir}/mimir.json"
gateway_query loki.ingest.localhost '/loki/api/v1/query_range?query=%7Bnamespace%3D%22telemetry-workloads%22%7D&limit=100' "${loki_result}"
gateway_query mimir.ingest.localhost '/prometheus/api/v1/query?query=telemetry_workload_heartbeat_total' "${mimir_result}"

[[ "$(gateway_status loki.ingest.localhost /loki/api/v1/labels full)" == "200" ]]
[[ "$(gateway_status loki.ingest.localhost /loki/api/v1/labels mtls)" == "401" ]]
set +e
basic_only_status="$(gateway_status loki.ingest.localhost /loki/api/v1/labels basic)"
basic_only_exit=$?
set -e
[[ "${basic_only_exit}" -ne 0 || "${basic_only_status}" != "200" ]]
policy_statuses="$(kubectl get securitypolicies.gateway.envoyproxy.io -A -o jsonpath='{range .items[*]}{range .status.ancestors[0].conditions[?(@.type=="Accepted")]}{.status}{"\n"}{end}{end}')"
[[ -n "${policy_statuses}" ]]
! grep -qv '^True$' <<< "${policy_statuses}"
echo "Gateway mTLS + Basic Auth regression checks passed."

ruby -rjson -e '
  data = JSON.parse(File.read(ARGV[0]))
  abort("Loki query was not successful") unless data["status"] == "success"
  streams = data.dig("data", "result") || []
  entries = streams.sum { |stream| (stream["values"] || []).length }
  abort("Loki telemetry entries are missing") if entries.zero?
  messages = streams.flat_map { |stream| (stream["values"] || []).map { |value| value[1] } }.join("\n")
  missing = %w[dotnet java go nodejs].reject { |language| messages.include?("language=#{language}") }
  abort("Loki is missing languages: #{missing.join(", ")}") unless missing.empty?
  puts "Loki telemetry streams=#{streams.length}, entries=#{entries}"
' "${loki_result}"
ruby -rjson -e '
  data = JSON.parse(File.read(ARGV[0]))
  abort("Mimir query was not successful") unless data["status"] == "success"
  series = data.dig("data", "result") || []
  abort("Mimir heartbeat series are missing") if series.empty?
  languages = series.map { |item| item.fetch("metric", {}).fetch("language", nil) }.compact.uniq
  missing = %w[dotnet java go nodejs] - languages
  abort("Mimir is missing languages: #{missing.join(", ")}") unless missing.empty?
  puts "Mimir heartbeat series=#{series.length}"
' "${mimir_result}"

port_log="${work_dir}/tempo-port-forward.log"
kubectl -n monitoring-stack-server port-forward service/tempo-query-frontend 13200:3200 >"${port_log}" 2>&1 &
forward_pid=$!

for _ in $(seq 1 20); do
  curl --silent --fail http://127.0.0.1:13200/ready >/dev/null 2>&1 && break
  sleep 1
done

for service_name in telemetry.dotnet telemetry.java telemetry.go telemetry.nodejs; do
  tempo_result="${work_dir}/tempo-${service_name}.json"
  curl --silent --show-error --fail --get --data-urlencode "tags=service.name=${service_name}" \
    http://127.0.0.1:13200/api/search > "${tempo_result}"
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV[0]))
    traces = data["traces"] || data.dig("data", "traces") || []
    abort("Tempo traces are missing for #{ARGV[1]}") if traces.empty?
    puts "Tempo #{ARGV[1]} traces=#{traces.length}"
  ' "${tempo_result}" "${service_name}"
done

pyroscope_logs="$(kubectl -n pyroscope logs statefulset/pyroscope --since=3m)"
for service_name in telemetry.java telemetry.go telemetry.nodejs; do
  grep -q "profile accepted.*service_name=${service_name}" <<<"${pyroscope_logs}"
done
echo "Pyroscope Java/Go/Node.js profile acceptance observed (.NET profile is architecture-dependent)."
