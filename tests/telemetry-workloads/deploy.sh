#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl config use-context kind-monitoring-local >/dev/null
kubectl apply -f "${script_dir}/kubernetes.yaml"
kubectl -n telemetry-workloads rollout status deployment/dotnet-telemetry --timeout=5m
kubectl -n telemetry-workloads rollout status deployment/java-telemetry --timeout=5m
kubectl -n telemetry-workloads rollout status deployment/go-telemetry --timeout=5m
kubectl -n telemetry-workloads rollout status deployment/nodejs-telemetry --timeout=5m
