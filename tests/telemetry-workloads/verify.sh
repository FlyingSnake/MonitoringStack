#!/usr/bin/env bash
set -euo pipefail

namespace="telemetry-workloads"
for app in dotnet java go nodejs; do
  kubectl -n "${namespace}" get deployment "${app}-telemetry" -o jsonpath='{.status.readyReplicas}' | grep -qx 1
  kubectl -n "${namespace}" logs "deployment/${app}-telemetry" --tail=20 | grep -q 'telemetry-workload heartbeat'
done

kubectl -n alloy get daemonset/alloy -o jsonpath='{.status.numberReady}' | grep -qx 1

echo "Workload readiness, stdout logs, and Alloy DaemonSet were observed. query.sh verifies Loki, Mimir, Tempo, and Pyroscope API results."
