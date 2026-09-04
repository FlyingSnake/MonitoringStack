#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture_dir="${script_dir}/agents/linux-ssh-fixture"
source "${script_dir}/lib.sh"

require_kind_cluster monitoring-local
"${fixture_dir}/create.sh"
cleanup() { "${fixture_dir}/destroy.sh"; }
trap cleanup EXIT

# The Linux fixture credential is intentionally runtime-only. Re-run the
# declarative AWX config after it exists so the temporary Machine Credential
# and Job Template are created without ever committing the SSH key.
kubectl -n argocd patch application awx-config --type=merge \
  -p '{"operation":{"sync":{"revision":"dev","prune":true,"syncStrategy":{"hook":{"force":true}}}}}' >/dev/null
for _ in $(seq 1 36); do
  phase="$(kubectl -n argocd get application awx-config -o jsonpath='{.status.operationState.phase}')"
  case "${phase}" in
    Succeeded) break ;;
    Failed|Error)
      echo "AWX config hook failed while registering the Linux fixture." >&2
      exit 1
      ;;
  esac
  sleep 5
done
[[ "${phase}" == "Succeeded" ]] || { echo "AWX config hook timed out while registering the Linux fixture." >&2; exit 1; }

"${script_dir}/awx-job.sh" 'Install Alloy - local Linux fixture'
"${fixture_dir}/verify.sh"
"${script_dir}/ui-api-smoke.sh"
echo "AWX Linux Alloy fixture smoke passed."
