#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl config use-context kind-monitoring-local >/dev/null
kubectl apply -f "${script_dir}/kubernetes.yaml"
for app in dotnet java go nodejs; do
  # The images use fixed local tags. Restarting makes a newly loaded Kind
  # image effective even when the Kubernetes manifest itself is unchanged.
  kubectl -n telemetry-workloads rollout restart "deployment/${app}-telemetry" >/dev/null
  kubectl -n telemetry-workloads rollout status "deployment/${app}-telemetry" --timeout=5m
done
