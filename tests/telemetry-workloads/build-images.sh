#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib.sh"
telemetry_load_config
images=(dotnet java go nodejs)

for image in "${images[@]}"; do
  docker build --tag "monitoring-stack/${image}-telemetry:0.1.0" "${script_dir}/apps/${image}"
  kind load docker-image --name "${telemetry_kind_cluster_name}" "monitoring-stack/${image}-telemetry:0.1.0"
done

echo "Telemetry workload images were built and loaded into ${telemetry_kind_cluster_name}."
