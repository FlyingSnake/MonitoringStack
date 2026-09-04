#!/usr/bin/env bash
set -euo pipefail

cluster_name="monitoring-local"
image="monitoring-stack-awx-ee:0.1.1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker build --tag "${image}" --file "${script_dir}/Containerfile" "${script_dir}"
kind load docker-image "${image}" --name "${cluster_name}"
echo "Loaded ${image} into kind-${cluster_name}."
