#!/usr/bin/env bash
set -euo pipefail

namespace="telemetry-workloads"
for app in dotnet java go nodejs; do
  observed=false
  for _ in $(seq 1 18); do
    if kubectl -n "${namespace}" get deployment "${app}-telemetry" -o jsonpath='{.status.readyReplicas}' | grep -qx 1 \
      && kubectl -n "${namespace}" logs "deployment/${app}-telemetry" --tail=50 2>/dev/null | grep -q 'telemetry-workload heartbeat'; then
      observed=true
      break
    fi
    sleep 5
  done
  [[ "${observed}" == "true" ]] || { echo "Timed out waiting for ${app} telemetry heartbeat." >&2; exit 1; }
done

kubectl -n alloy get daemonset/alloy -o jsonpath='{.status.numberReady}' | grep -qx 1
sleep 5

echo "Workload readiness, stdout logs, and Alloy DaemonSet were observed. query.sh verifies Loki, Mimir, Tempo, and Pyroscope API results."
