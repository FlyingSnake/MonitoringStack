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
      agent.fetch("endpoints").each_value do |url|
        abort("#{target} agent endpoint does not match environment domain: #{url}") unless url.include?(".#{environment}.")
      end
    end
  end
' "${environment}" "${values_file}" "${overlay_file}" "${rendered_file}"

echo "${environment} server and agent contract preflight passed."
