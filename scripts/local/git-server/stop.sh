#!/usr/bin/env bash
set -euo pipefail

container_name="monitoring-local-git"
if docker ps -a --format '{{.Names}}' | grep -qx "${container_name}"; then
  docker stop "${container_name}" >/dev/null
  docker rm "${container_name}" >/dev/null
  echo "Local Git daemon stopped."
else
  echo "Local Git daemon is not running."
fi
