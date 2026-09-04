#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cluster_name="monitoring-local"
images=(dotnet java go nodejs)

for image in "${images[@]}"; do
  docker build --tag "monitoring-stack/${image}-telemetry:0.1.0" "${script_dir}/apps/${image}"
  kind load docker-image --name "${cluster_name}" "monitoring-stack/${image}-telemetry:0.1.0"
done

echo "Telemetry workload images were built and loaded into ${cluster_name}."
