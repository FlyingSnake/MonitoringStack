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
  while IFS= read -r metadata; do
    chart="$(dirname "${metadata}")"
    helm lint "${chart}"
    rendered="/tmp/$(basename "${chart}").yaml"
    helm template "$(basename "${chart}")" "${chart}" > "${rendered}"
    ruby -e 'require "yaml"; YAML.load_stream(File.read(ARGV[0]))' "${rendered}"
  done < <(find server/charts -mindepth 2 -maxdepth 2 -name Chart.yaml | sort)

  if [[ -f local/server/values.yaml ]]; then
    helm lint server/charts/platform-apps \
      -f server/values/common.yaml \
      -f server/env/dev/values.yaml \
      -f local/server/values.yaml
    helm template monitoring-platform-local server/charts/platform-apps \
      -f server/values/common.yaml \
      -f server/env/dev/values.yaml \
      -f local/server/values.yaml > /tmp/monitoring-platform-local.yaml
    ruby -e 'require "yaml"; YAML.load_stream(File.read(ARGV[0]))' /tmp/monitoring-platform-local.yaml
  fi

  external_helm_check
}

external_helm_check() {
  helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
  helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
  helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
  helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
  helm repo add grafana-community https://grafana-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add redpanda https://charts.redpanda.com >/dev/null 2>&1 || true
  helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm >/dev/null 2>&1 || true
  helm repo update >/dev/null

  for environment in dev stg prd; do
    rendered="/tmp/monitoring-platform-${environment}.yaml"
    helm template "monitoring-platform-${environment}" server/charts/platform-apps \
      -f server/values/common.yaml \
      -f "server/env/${environment}/values.yaml" > "${rendered}"
    metadata="/tmp/monitoring-external-${environment}.tsv"
    ruby -ryaml -e '
      output_dir = ARGV.fetch(1)
      YAML.load_stream(File.read(ARGV.fetch(0))).compact.each do |resource|
        next unless resource["kind"] == "Application"
        source = resource.dig("spec", "source")
        next unless source && source["chart"]
        name = resource.dig("metadata", "name")
        values = YAML.dump(source.dig("helm", "valuesObject") || {}).sub(/\A---\s*/, "")
        File.write(File.join(output_dir, "#{name}.yaml"), values)
        puts [name, source["repoURL"], source["chart"], source["targetRevision"], resource.dig("spec", "destination", "namespace")].join("\t")
      end
    ' "${rendered}" /tmp > "${metadata}"

    while IFS=$'\t' read -r name repo_url chart version namespace; do
      case "${repo_url}" in
        https://helm.releases.hashicorp.com) repository=hashicorp ;;
        https://charts.jetstack.io) repository=jetstack ;;
        https://charts.external-secrets.io) repository=external-secrets ;;
        https://charts.bitnami.com/bitnami) repository=bitnami ;;
        https://grafana-community.github.io/helm-charts) repository=grafana-community ;;
        https://grafana.github.io/helm-charts) repository=grafana ;;
        https://prometheus-community.github.io/helm-charts) repository=prometheus-community ;;
        https://charts.redpanda.com) repository=redpanda ;;
        https://ansible-community.github.io/awx-operator-helm) repository=awx-operator ;;
        *) echo "Unsupported Helm repository in ${name}: ${repo_url}" >&2; exit 1 ;;
      esac
      output="/tmp/monitoring-external-${environment}-${name}.yaml"
      helm template "${name}" "${repository}/${chart}" \
        --version "${version}" \
        --namespace "${namespace}" \
        --values "/tmp/${name}.yaml" > "${output}"
      ruby -e 'require "yaml"; YAML.load_stream(File.read(ARGV[0]))' "${output}"
    done < "${metadata}"
  done
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
