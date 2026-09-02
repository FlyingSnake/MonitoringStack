#!/usr/bin/env bash
set -euo pipefail

environment="${1:?usage: scripts/preflight-server-env.sh <stg|prd>}"
values_file="server/env/${environment}/values.yaml"

if [[ "${environment}" != "stg" && "${environment}" != "prd" ]]; then
  echo "Only stg and prd require the production contract preflight." >&2
  exit 2
fi

if rg --quiet 'REQUIRED_[A-Z0-9_]+' "${values_file}"; then
  echo "${environment} values still contain REQUIRED_* placeholders. Refusing deployment." >&2
  rg -n 'REQUIRED_[A-Z0-9_]+' "${values_file}" >&2
  exit 1
fi

if rg --quiet 'example\.internal' "${values_file}"; then
  echo "${environment} values still contain the example.internal domain. Refusing deployment." >&2
  rg -n 'example\.internal' "${values_file}" >&2
  exit 1
fi

rendered_file="$(mktemp)"
helm template "monitoring-platform-${environment}" server/charts/platform-apps \
  -f server/values/common.yaml \
  -f "${values_file}" > "${rendered_file}"

ruby -ryaml -e '
  environment, values_path, rendered_path = ARGV
  values = YAML.load_file(values_path)
  base_domain = values.fetch("baseDomain")
  abort("baseDomain must be a concrete non-example domain") if base_domain.empty? || base_domain == "example.internal"

  applications = YAML.load_stream(File.read(rendered_path)).compact
  find_application = lambda do |name|
    application = applications.find { |item| item.dig("kind") == "Application" && item.dig("metadata", "name") == name }
    abort("Missing Application: #{name}") unless application
    application
  end
  application_values = lambda do |name|
    find_application.call(name).dig("spec", "source", "helm", "valuesObject") || {}
  end

  vault = application_values.call("vault")
  vault_config = vault.dig("server", "ha", "raft", "config").to_s
  abort("Vault AWS KMS auto-unseal configuration is required") unless vault_config.include?("seal \"awskms\"")
  irsa_role = vault.dig("server", "serviceAccount", "annotations", "eks.amazonaws.com/role-arn").to_s
  abort("Vault IRSA role ARN is required") if irsa_role.empty?

  gateway = application_values.call("platform-gateway").fetch("gateway")
  %w[name namespace uiListener ingestListener].each do |key|
    abort("Gateway #{key} is required") if gateway[key].to_s.empty?
  end
  expected_suffix = ".#{environment}.#{base_domain}"
  hosts = (gateway.fetch("tls").fetch("uiDnsNames") + gateway.fetch("tls").fetch("ingestDnsNames"))
  abort("Gateway DNS names do not match #{expected_suffix}") unless hosts.all? { |host| host.end_with?(expected_suffix) }

  if environment == "prd"
    %w[loki mimir tempo pyroscope].each do |name|
      application_values.call(name)
    end
    %w[minio redpanda].each do |name|
      abort("#{name} must not be deployed in prd") if applications.any? { |item| item.dig("kind") == "Application" && item.dig("metadata", "name") == name }
    end
  end
 ' "${environment}" "${values_file}" "${rendered_file}"

echo "${environment} server values preflight passed."
