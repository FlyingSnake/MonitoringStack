#!/usr/bin/env bash
set -euo pipefail

container_name="monitoring-local-git"
# alpine/git intentionally omits the git-daemon subcommand.  The base Alpine
# image installs the small git-daemon package at container start instead.
image="alpine:3.20"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
runtime_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"
repository_dir="${runtime_dir}/git-server/repositories/MonitoringStack.git"

"${script_dir}/refresh.sh"

if docker ps --format '{{.Names}}' | grep -qx "${container_name}"; then
  echo "Local Git daemon is already running."
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "${container_name}"; then
  # An older container may have been created with the image's `git` entrypoint,
  # which turns `git daemon` into the invalid `git git daemon` command.
  docker rm -f "${container_name}" >/dev/null
fi

docker run --detach \
  --name "${container_name}" \
  --publish 9418:9418 \
  --volume "${runtime_dir}/git-server/repositories:/repos:ro" \
  --entrypoint /bin/sh \
  "${image}" \
  -c 'apk add --no-cache git-daemon >/dev/null && exec git daemon --reuseaddr --verbose --base-path=/repos --export-all /repos' >/dev/null

echo "Local Git daemon: git://host.docker.internal:9418/MonitoringStack.git"
