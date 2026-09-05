#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

for environment in dev stg prd; do
  values_file="agents/env/${environment}/windows/values.yaml"
  expected_revision="${environment}"
  [[ "${environment}" == "prd" ]] && expected_revision="main"

  ruby -ryaml -e '
    environment, revision, values_file = ARGV
    values = YAML.load_file(values_file)
    failures = []
    failures << "environment" unless values["environment"] == environment
    failures << "enabled" unless values["enabled"] == true
    failures << "inventory.source" unless values.dig("inventory", "source") == "agents/ansible/inventories/#{environment}/windows/hosts.yml"
    failures << "alloy.version" unless values.dig("alloy", "version").to_s.match?(/\A\d+\.\d+\.\d+\z/)
    failures << "alloy.config.revision" unless values.dig("alloy", "config", "revision") == revision
    failures << "alloy.config.modulePath" unless values.dig("alloy", "config", "modulePath") == "agents/alloy/modules/windows/alloy.alloy"
    %w[loki mimir tempoHttp pyroscope].each do |endpoint|
      value = values.dig("endpoints", endpoint).to_s
      failures << "endpoints.#{endpoint}" unless value.start_with?("https://") && value.include?(".ingest.#{environment}.")
    end
    failures << "security.authSecretRef" if values.dig("security", "authSecretRef").to_s.empty?
    failures << "security.tlsSecretRef" if values.dig("security", "tlsSecretRef").to_s.empty?
    %w[logs metrics traces].each do |feature|
      failures << "features.#{feature}" unless values.dig("features", feature) == true
    end
    abort "Windows environment contract failed (#{values_file}): #{failures.join(", ")}" unless failures.empty?
  ' "${environment}" "${expected_revision}" "${values_file}"
done

required_files=(
  agents/ansible/inventories/dev/windows/hosts.yml
  agents/ansible/inventories/stg/windows/hosts.yml
  agents/ansible/inventories/prd/windows/hosts.yml
  agents/ansible/inventories/dev/windows/group_vars/alloy_windows.yaml
  agents/ansible/inventories/stg/windows/group_vars/alloy_windows.yaml
  agents/ansible/inventories/prd/windows/group_vars/alloy_windows.yaml
  agents/ansible/playbooks/install-alloy-windows.yaml
  agents/ansible/roles/grafana_alloy_windows/tasks/main.yaml
  agents/ansible/roles/grafana_alloy_windows_credentials/tasks/main.yaml
  agents/alloy/modules/windows/alloy.alloy
)

for file in "${required_files[@]}"; do
  [[ -f "${file}" ]] || { echo "Missing Windows contract file: ${file}" >&2; exit 1; }
done

for group_vars in agents/ansible/inventories/*/windows/group_vars/alloy_windows.yaml; do
  ruby -ryaml -e '
    values = YAML.load_file(ARGV.fetch(0))
    required = {
      "ansible_connection" => "winrm",
      "ansible_port" => 5986,
      "ansible_winrm_scheme" => "https",
      "ansible_winrm_server_cert_validation" => "validate"
    }
    failures = required.each_with_object([]) do |(key, value), result|
      result << key unless values[key] == value
    end
    abort "Windows WinRM security contract failed (#{ARGV.fetch(0)}): #{failures.join(", ")}" unless failures.empty?
  ' "${group_vars}"
done

rg -q 'ansible\.windows\.win_package' agents/ansible/roles/grafana_alloy_windows/tasks/main.yaml
rg -q 'ansible\.windows\.win_service' agents/ansible/roles/grafana_alloy_windows/tasks/main.yaml
rg -q 'ansible\.windows\.win_acl_inheritance' agents/ansible/roles/grafana_alloy_windows_credentials/tasks/main.yaml
rg -q 'pki_int/issue/monitoring-client' agents/ansible/roles/grafana_alloy_windows_credentials/defaults/main.yaml
rg -q 'import\.git' agents/ansible/roles/grafana_alloy_windows/templates/config.alloy.j2
rg -q 'EventLog|eventlog' agents/alloy/modules/windows/alloy.alloy
rg -q 'alloyWindowsEnvironment' server/charts/awx-config/templates/config.yaml
rg -q 'windowsCredential' server/charts/awx-config/templates/config.yaml
rg -q 'additionalExternalSecrets' server/charts/platform-secrets/templates/secrets.yaml

echo "Windows Alloy declaration contract is valid for dev, stg, and prd."
