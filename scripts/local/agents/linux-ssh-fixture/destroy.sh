#!/usr/bin/env bash
set -euo pipefail

fixture_name="monitoring-linux-alloy-fixture"
profile_emitter_name="monitoring-linux-alloy-profile-emitter"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
runtime_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"
state_dir="${runtime_dir}/agents/linux-ssh-fixture/.state"
if docker ps -a --format '{{.Names}}' | grep -qx "${profile_emitter_name}"; then
  docker rm --force "${profile_emitter_name}" >/dev/null
fi
if docker ps -a --format '{{.Names}}' | grep -qx "${fixture_name}"; then
  docker rm --force "${fixture_name}" >/dev/null
fi
kubectl -n awx delete secret monitoring-linux-test-ssh --ignore-not-found >/dev/null
if kubectl -n awx get deployment monitoring-awx-task >/dev/null 2>&1; then
  kubectl -n awx exec deployment/monitoring-awx-task -c monitoring-awx-task -- \
    awx-manage shell -c 'from awx.main.models import Credential; Credential.objects.filter(name="MonitoringStack Local Linux SSH").delete()' \
    >/dev/null
fi
rm -f "${state_dir}/id_ed25519" "${state_dir}/id_ed25519.pub"
echo "Local Linux fixture/profile emitter, Kubernetes SSH Secret, AWX Machine Credential, and one-time SSH key were removed."
