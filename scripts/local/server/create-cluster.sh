#!/usr/bin/env bash
set -euo pipefail

cluster_name="monitoring-local"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if kind get clusters | grep -qx "${cluster_name}"; then
  echo "kind cluster ${cluster_name} already exists"
  exit 0
fi

kind create cluster --name "${cluster_name}" --config "${script_dir}/kind-config.yaml"
kubectl config use-context "kind-${cluster_name}"
kubectl cluster-info
