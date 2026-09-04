#!/usr/bin/env bash
set -euo pipefail

namespace="telemetry-workloads"
for app in dotnet java go nodejs; do
  kubectl -n "${namespace}" get deployment "${app}-telemetry" -o jsonpath='{.status.readyReplicas}' | grep -qx 1
  kubectl -n "${namespace}" logs "deployment/${app}-telemetry" --tail=20 | grep -q 'telemetry-workload heartbeat'
done

kubectl -n alloy get daemonset/alloy -o jsonpath='{.status.numberReady}' | grep -qx 1
for service in telemetry.go telemetry.java telemetry.nodejs; do
  kubectl -n pyroscope logs statefulset/pyroscope --since=3m | grep -q "profile accepted.*service_name=${service}"
done

echo "Workload readiness, stdout logs, Alloy DaemonSet, and Go/Java/Node.js profile acceptance were observed. Run query.sh for Loki, Mimir, and Tempo queries."
