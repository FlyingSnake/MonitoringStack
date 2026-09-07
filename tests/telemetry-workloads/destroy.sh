#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib.sh"
telemetry_load_config
kubectl config use-context "${telemetry_cluster_context}" >/dev/null
kubectl delete -f "${script_dir}/kubernetes.yaml" --ignore-not-found
