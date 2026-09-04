#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib.sh"

require_kind_cluster monitoring-local
"${script_dir}/awx-job.sh" 'Install Alloy - dev Kubernetes'
kubectl -n alloy rollout status daemonset/alloy --timeout=5m
kubectl -n alloy get secret alloy-ingest-client -o jsonpath='{.data.ca\.crt}' | grep -q .
kubectl -n alloy get secret alloy-ingest-client -o jsonpath='{.data.tls\.crt}' | grep -q .
kubectl -n alloy get secret alloy-ingest-client -o jsonpath='{.data.tls\.key}' | grep -q .
echo "AWX Kubernetes Alloy deployment, Vault-issued Secret, and DaemonSet readiness passed."
