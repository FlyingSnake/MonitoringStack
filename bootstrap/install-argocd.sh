#!/usr/bin/env bash
set -euo pipefail

environment="${ENVIRONMENT:?ENVIRONMENT must be dev, stg, or prd}"
case "${environment}" in
  dev|stg|prd) ;;
  *) echo "ENVIRONMENT must be dev, stg, or prd" >&2; exit 1 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_values="${repo_root}/server/env/${environment}/values.yaml"
bootstrap_override="$(mktemp)"
trap 'rm -f "${bootstrap_override}"' EXIT

# Argo CD는 최초에는 Helm으로 설치되므로 Application values를 읽을 수 없다.
# OIDC issuer, Argo CD 도메인, 그룹 RBAC은 server 환경 계약에서 일회성 Helm
# override로 렌더링해 별도 bootstrap/oidc 파일과의 drift를 없앤다.
ruby -ryaml -e '
  values_path, output_path, oidc_enabled = ARGV
  values = YAML.load_file(values_path)
  platform = values.fetch("platform")
  hosts = platform.fetch("hosts")
  identity = platform.fetch("identity")
  groups = identity.fetch("groups")
  output = {
    "global" => { "domain" => hosts.fetch("argocd") },
    "configs" => {
      "rbac" => {
        "policy.default" => "role:readonly",
        "policy.csv" => "g, #{groups.fetch("platformAdmin")}, role:admin\\ng, #{groups.fetch("observabilityViewer")}, role:readonly"
      }
    }
  }
  if oidc_enabled == "true"
    output["configs"]["cm"] = {
      "oidc.config" => "name: Keycloak\\nissuer: https://#{hosts.fetch("keycloak")}/realms/#{identity.fetch("realm")}\\nclientID: argocd\\nclientSecret: $oidc.keycloak.clientSecret\\nrequestedScopes: [\\\"openid\\\", \\\"profile\\\", \\\"email\\\", \\\"groups\\\"]"
    }
  end
  File.write(output_path, YAML.dump(output))
' "${environment_values}" "${bootstrap_override}" "$([[ "${1:-}" == "--enable-oidc" ]] && echo true || echo false)"
helm_args=(
  upgrade --install argocd argo/argo-cd
  --namespace argocd
  --create-namespace
  --version 10.4.1
  --values "${repo_root}/bootstrap/argocd/values.yaml"
  --values "${bootstrap_override}"
)

helm "${helm_args[@]}"
