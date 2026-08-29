#!/usr/bin/env bash
set -euo pipefail

mode="${1:-all}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

yaml_check() {
  while IFS= read -r file; do
    ruby -e 'require "yaml"; YAML.load_stream(File.read(ARGV[0]))' "${file}"
  done < <(find bootstrap server agents -type f \( -name '*.yaml' -o -name '*.yml' \) ! -path '*/templates/*' | sort)
}

helm_check() {
  for environment in dev stg prd; do
    helm lint server/charts/platform-apps -f server/values/common.yaml -f "server/env/${environment}/values.yaml"
    helm template "monitoring-platform-${environment}" server/charts/platform-apps \
      -f server/values/common.yaml \
      -f "server/env/${environment}/values.yaml" > "/tmp/monitoring-platform-${environment}.yaml"
    ruby -e 'require "yaml"; YAML.load_stream(File.read(ARGV[0]))' "/tmp/monitoring-platform-${environment}.yaml"
  done
  helm lint server/charts/platform-resources
  helm lint server/charts/awx-resources
}

ansible_check() {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ansible-playbook is not installed; skipping local Ansible syntax check" >&2
    return 0
  fi

  for playbook in agents/ansible/playbooks/*.yaml; do
    ansible-playbook --syntax-check "${playbook}"
  done
}

case "${mode}" in
  all)
    yaml_check
    helm_check
    ansible_check
    ;;
  yaml) yaml_check ;;
  helm) helm_check ;;
  ansible) ansible_check ;;
  *) echo "usage: $0 [all|yaml|helm|ansible]" >&2; exit 2 ;;
esac
