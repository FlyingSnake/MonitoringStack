#!/usr/bin/env bash
set -euo pipefail

fixture_name="monitoring-linux-alloy-fixture"
image_name="monitoring-stack/linux-alloy-fixture:24.04"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
runtime_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"
state_dir="${runtime_dir}/agents/linux-ssh-fixture/.state"
private_key="${state_dir}/id_ed25519"
public_key="${private_key}.pub"

mkdir -p "${state_dir}"
chmod 0700 "${state_dir}"
if [[ ! -f "${private_key}" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "${private_key}"
  chmod 0600 "${private_key}"
fi

docker build --tag "${image_name}" "${script_dir}"
if docker ps -a --format '{{.Names}}' | grep -qx "${fixture_name}"; then
  docker start "${fixture_name}" >/dev/null
else
  docker run --detach --privileged --cgroupns=host \
    --name "${fixture_name}" \
    --publish 2222:22 \
    --tmpfs /run --tmpfs /run/lock \
    --add-host host.docker.internal:host-gateway \
    --add-host loki-ingest.demo.flyingsnake.xyz:host-gateway \
    --add-host mimir-ingest.demo.flyingsnake.xyz:host-gateway \
    --add-host tempo-ingest.demo.flyingsnake.xyz:host-gateway \
    --add-host pyroscope-ingest.demo.flyingsnake.xyz:host-gateway \
    --volume "${public_key}:/run/fixture/authorized_keys:ro" \
    "${image_name}" >/dev/null
fi

for _ in $(seq 1 30); do
  if ssh -i "${private_key}" -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 alloytest@127.0.0.1 true 2>/dev/null; then
    break
  fi
  sleep 1
done

ssh -i "${private_key}" -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 alloytest@127.0.0.1 true
kubectl -n awx create secret generic monitoring-linux-test-ssh \
  --from-file=ssh-privatekey="${private_key}" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "Local Linux fixture is ready on host.docker.internal:2222."
