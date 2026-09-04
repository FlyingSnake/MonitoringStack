#!/usr/bin/env bash

set -euo pipefail

monitoring_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

monitoring_runtime_dir() {
  local repo_root
  repo_root="$(monitoring_repo_root)"
  printf '%s\n' "${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"
}

require_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is unavailable. Start Docker Desktop, then retry." >&2
    exit 1
  fi
}

require_kind_cluster() {
  local cluster_name="${1:-monitoring-local}"
  require_docker
  if ! kind get clusters | grep -qx "${cluster_name}"; then
    echo "Kind cluster '${cluster_name}' is unavailable. Run scripts/local/server/create-cluster.sh first." >&2
    exit 1
  fi
  kubectl config use-context "kind-${cluster_name}" >/dev/null
}

require_local_values() {
  local runtime_dir
  runtime_dir="$(monitoring_runtime_dir)"
  if [[ ! -f "${runtime_dir}/server/values.yaml" ]]; then
    echo "Local values are unavailable: ${runtime_dir}/server/values.yaml" >&2
    echo "Create the local runtime values file before bootstrapping the Kind stack." >&2
    exit 1
  fi
}
