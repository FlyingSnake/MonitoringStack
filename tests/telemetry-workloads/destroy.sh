#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl config use-context kind-monitoring-local >/dev/null
kubectl delete -f "${script_dir}/kubernetes.yaml" --ignore-not-found
