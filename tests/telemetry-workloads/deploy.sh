#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib.sh"
telemetry_load_config
kubectl config use-context "${telemetry_cluster_context}" >/dev/null
kubectl apply -f "${script_dir}/kubernetes.yaml"
for app in dotnet java go nodejs; do
  # The images use fixed local tags. Restarting makes a newly loaded Kind
  # image effective even when the Kubernetes manifest itself is unchanged.
  kubectl -n "${telemetry_namespace}" rollout restart "deployment/${app}-telemetry" >/dev/null
  kubectl -n "${telemetry_namespace}" rollout status "deployment/${app}-telemetry" --timeout=5m
done
