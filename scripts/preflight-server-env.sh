#!/usr/bin/env bash
set -euo pipefail

environment="${1:?usage: scripts/preflight-server-env.sh <dev|stg|prd> [overlay-values.yaml]}"
overlay_file="${2:-}"
values_file="server/env/${environment}/values.yaml"

case "${environment}" in
  dev|stg|prd) ;;
  *) echo "environment must be dev, stg, or prd" >&2; exit 2 ;;
esac
[[ -f "${values_file}" ]] || { echo "Missing values file: ${values_file}" >&2; exit 1; }
if [[ -n "${overlay_file}" && ! -f "${overlay_file}" ]]; then
  echo "Overlay values file does not exist: ${overlay_file}" >&2
  exit 1
fi

rendered_file="$(mktemp)"
trap 'rm -f "${rendered_file}"' EXIT
helm_args=(template "monitoring-platform-${environment}" server/charts/platform-apps -f server/values/common.yaml -f "${values_file}")
[[ -n "${overlay_file}" ]] && helm_args+=(-f "${overlay_file}")
helm "${helm_args[@]}" > "${rendered_file}"

ruby -ryaml -e '
  environment, values_path, overlay_path, rendered_path = ARGV
  environment_values = YAML.load_file(values_path)
  platform = environment_values.fetch("platform")
  platform_namespaces = platform.fetch("namespaces")
  platform_vault = platform.fetch("vault")
  platform_storage = platform.fetch("objectStorage")
  platform_kafka = platform.fetch("kafka")
  platform_hosts = platform.fetch("hosts")
  platform_identity = platform.fetch("identity")
  applications = YAML.load_stream(File.read(rendered_path)).compact
  find_application = lambda do |name|
    application = applications.find { |item| item.dig("kind") == "Application" && item.dig("metadata", "name") == name }
    abort("Missing Application: #{name}") unless application
    application
  end
  application_values = lambda { |name| find_application.call(name).dig("spec", "source", "helm", "valuesObject") || {} }
  reject_placeholders = lambda do |value, context|
    serialized = YAML.dump(value)
    abort("#{context} contains REQUIRED_* placeholder") if serialized.match?(/REQUIRED_[A-Z0-9_]+/)
    abort("#{context} contains example.internal") if serialized.include?("example.internal")
  end

  applications.each { |application| reject_placeholders.call(application, "rendered #{application.dig("metadata", "name")}") }

  abort("platform monitoring namespace is required") if platform_namespaces.fetch("monitoring").to_s.empty?
  %w[address kvMount kubernetesAuthMount].each { |key| abort("platform vault #{key} is required") if platform_vault.fetch(key).to_s.empty? }
  %w[secretStore gatewayIssuer keycloakConfig awxAgent].each { |key| abort("platform vault role #{key} is required") if platform_vault.fetch("roles").fetch(key).to_s.empty? }
  %w[ingestion oidc gatewaySign].each { |key| abort("platform vault path #{key} is required") if platform_vault.fetch("paths").fetch(key).to_s.empty? }
  abort("platform object storage endpoint is required") if platform_storage.fetch("endpoint").to_s.empty?
  abort("platform object storage insecure must be boolean") unless [true, false].include?(platform_storage.fetch("insecure"))
  %w[loki tempo mimirBlocks mimirRuler mimirAlertmanager pyroscope].each do |bucket|
    abort("platform object storage bucket #{bucket} is required") if platform_storage.fetch("buckets").fetch(bucket).to_s.empty?
  end
  abort("platform Kafka brokers are required") if platform_kafka.fetch("brokers").empty?
  %w[mimirIngest tempo].each { |topic| abort("platform Kafka topic #{topic} is required") if platform_kafka.fetch("topics").fetch(topic).to_s.empty? }
  abort("platform identity realm is required") if platform_identity.fetch("realm").to_s.empty?

  loki_storage = application_values.call("loki").dig("loki", "storage") || {}
  abort("Loki bucket does not match platform object storage contract") unless loki_storage.dig("bucketNames", "chunks") == platform_storage.dig("buckets", "loki")
  mimir_config = application_values.call("mimir").dig("mimir", "structuredConfig") || {}
  abort("Mimir blocks bucket does not match platform object storage contract") unless mimir_config.dig("blocks_storage", "s3", "bucket_name") == platform_storage.dig("buckets", "mimirBlocks")
  mimir_kafka = mimir_config.dig("ingest_storage", "kafka") || {}
  abort("Mimir Kafka topic does not match platform Kafka contract") unless mimir_kafka["topic"] == platform_kafka.dig("topics", "mimirIngest")
  tempo_values = application_values.call("tempo")
  abort("Tempo bucket does not match platform object storage contract") unless tempo_values.dig("storage", "trace", "s3", "bucket") == platform_storage.dig("buckets", "tempo")
  abort("Tempo Kafka topic does not match platform Kafka contract") unless tempo_values.dig("traces", "kafka", "topic") == platform_kafka.dig("topics", "tempo")

  gateway = application_values.call("platform-gateway").fetch("gateway")
  %w[name namespace uiListener ingestListener].each { |key| abort("Gateway #{key} is required") if gateway[key].to_s.empty? }
  tls = gateway.fetch("tls")
  hosts = tls.fetch("uiDnsNames") + tls.fetch("ingestDnsNames")
  abort("Gateway TLS names are required") if hosts.empty? || hosts.uniq.length != hosts.length
  localhost_overlay = hosts.all? { |host| host.end_with?(".localhost") }
  demo_overlay = hosts.all? { |host| host.end_with?(".demo.flyingsnake.xyz") }
  if localhost_overlay
    abort("Local UI hosts must use .ui.localhost") unless tls.fetch("uiDnsNames").all? { |host| host.end_with?(".ui.localhost") }
    abort("Local ingest hosts must use .ingest.localhost") unless tls.fetch("ingestDnsNames").all? { |host| host.end_with?(".ingest.localhost") }
  elsif demo_overlay
    expected_ui = %w[grafana argocd keycloak awx].map { |name| "#{name}.demo.flyingsnake.xyz" }
    expected_ingest = %w[loki mimir tempo pyroscope].map { |name| "#{name}-ingest.demo.flyingsnake.xyz" }
    abort("Local demo UI hosts do not match the Lets Encrypt wildcard contract") unless tls.fetch("uiDnsNames").sort == expected_ui.sort
    abort("Local demo ingest hosts do not match the Lets Encrypt wildcard contract") unless tls.fetch("ingestDnsNames").sort == expected_ingest.sort
    abort("Local demo must use externally managed Lets Encrypt TLS Secrets") unless tls["managedByCertManager"] == false
    abort("Local demo UI routes must bind to explicit TLS listeners") unless gateway.fetch("uiRoutes").all? { |route| route["listener"].to_s.end_with?("-ui-https") }
    abort("Local demo ingest routes must bind to explicit HTTPS listeners") unless gateway.fetch("ingestionRoutes").all? { |route| route["listener"].to_s.end_with?("-ingest-https") }
  else
    expected_fragment = ".#{environment}."
    abort("Gateway DNS names do not match #{environment} environment") unless hosts.all? { |host| host.include?(expected_fragment) }
  end

  unless localhost_overlay || demo_overlay
    expected_hosts = {
      "grafana" => platform_hosts.fetch("grafana"), "argocd" => platform_hosts.fetch("argocd"),
      "keycloak" => platform_hosts.fetch("keycloak"), "awx" => platform_hosts.fetch("awx"),
      "loki-ingest" => platform_hosts.fetch("lokiIngest"), "mimir-ingest" => platform_hosts.fetch("mimirIngest"),
      "tempo-ingest" => platform_hosts.fetch("tempoIngest"), "pyroscope-ingest" => platform_hosts.fetch("pyroscopeIngest")
    }
    (gateway.fetch("uiRoutes") + gateway.fetch("ingestionRoutes")).each do |route|
      abort("Gateway host contract does not match platform.hosts for #{route.fetch("name")}") unless route.fetch("hostname") == expected_hosts.fetch(route.fetch("name"))
    end
  end

  vault = application_values.call("vault")
  vault_config = vault.dig("server", "ha", "raft", "config").to_s
  if environment == "dev"
    abort("dev Vault must not use AWS KMS auto-unseal") if vault_config.include?("seal \"awskms\"")
  else
    abort("Vault AWS KMS auto-unseal configuration is required") unless vault_config.include?("seal \"awskms\"")
    irsa_role = vault.dig("server", "serviceAccount", "annotations", "eks.amazonaws.com/role-arn").to_s
    abort("Vault IRSA role ARN is required") if irsa_role.empty?
  end

  if environment == "prd"
    %w[minio redpanda].each do |name|
      abort("#{name} must not be deployed in prd") if applications.any? { |item| item.dig("kind") == "Application" && item.dig("metadata", "name") == name }
    end
    prd_serialized = %w[loki mimir tempo pyroscope].map { |name| YAML.dump(application_values.call(name)) }.join
    abort("prd requires concrete external S3 and Kafka values") if prd_serialized.match?(/REQUIRED_(S3_ENDPOINT|KAFKA_BROKER)/)
  else
    %w[minio redpanda].each { |name| find_application.call(name) }
  end

  unless localhost_overlay || demo_overlay
    expected_revision = { "dev" => "dev", "stg" => "stg", "prd" => "main" }.fetch(environment)
    %w[linux windows k8s].each do |target|
      agent = YAML.load_file("agents/env/#{environment}/#{target}/values.yaml")
      abort("#{target} agent revision must be #{expected_revision}") unless agent.dig("alloy", "config", "revision") == expected_revision
      endpoints = agent.fetch("endpoints")
      expected_endpoints = {
        "loki" => "https://#{platform_hosts.fetch("lokiIngest")}/loki/api/v1/push",
        "mimir" => "https://#{platform_hosts.fetch("mimirIngest")}/api/v1/push",
        "tempoHttp" => "https://#{platform_hosts.fetch("tempoIngest")}",
        "pyroscope" => "https://#{platform_hosts.fetch("pyroscopeIngest") }"
      }
      abort("#{target} agent endpoint contract differs from platform.hosts") unless endpoints == expected_endpoints
      automation_vault = agent.dig("automation", "vault") || {}
      abort("#{target} agent Vault automation contract is incomplete") unless %w[address kubernetesRole ingestionPath].all? { |key| automation_vault[key].to_s.length > 0 }
    end
  end
' "${environment}" "${values_file}" "${overlay_file}" "${rendered_file}"

echo "${environment} server and agent contract preflight passed."
