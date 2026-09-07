#!/usr/bin/env bash

telemetry_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
telemetry_values_file="${telemetry_script_dir}/values.yaml"

telemetry_value() {
  ruby -ryaml -e 'puts ARGV.drop(1).reduce(YAML.load_file(ARGV.fetch(0))) { |value, key| value.fetch(key) }' "$@"
}

telemetry_load_config() {
  [[ -f "${telemetry_values_file}" ]] || { echo "Telemetry smoke values are unavailable: ${telemetry_values_file}" >&2; return 1; }
  telemetry_cluster_context="$(telemetry_value "${telemetry_values_file}" clusterContext)"
  telemetry_kind_cluster_name="$(telemetry_value "${telemetry_values_file}" kindClusterName)"
  telemetry_namespace="$(telemetry_value "${telemetry_values_file}" namespace)"
}
