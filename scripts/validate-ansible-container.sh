#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${AWX_EE_IMAGE:-monitoring-stack-awx-ee:0.1.0}"

if ! docker image inspect "${image}" >/dev/null 2>&1; then
  echo "AWX execution environment image is unavailable: ${image}" >&2
  echo "Build local/server/awx-ee first or set AWX_EE_IMAGE to a fixed compatible image." >&2
  exit 1
fi

docker run --rm \
  --volume "${repo_root}:/workspace:ro" \
  --workdir /workspace \
  "${image}" \
  /bin/sh -ec '
    ansible-inventory -i agents/ansible/inventories/dev/linux/hosts.yml --graph
    ansible-inventory -i agents/ansible/inventories/dev/windows/hosts.yml --graph
    for playbook in agents/ansible/playbooks/*.yaml; do
      ansible-playbook --syntax-check "$playbook"
    done
  '
