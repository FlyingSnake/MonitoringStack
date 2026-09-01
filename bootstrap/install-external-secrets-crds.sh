#!/usr/bin/env bash
set -euo pipefail

# ESO CRD schemas exceed Kubernetes' client-side apply annotation limit.
# Bootstrap them once with server-side apply before the Argo CD ESO Application.
chart_version="2.10.0"
namespace="external-secrets"
temp_file="$(mktemp)"
trap 'rm -f "${temp_file}"' EXIT

helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm template external-secrets external-secrets/external-secrets \
  --version "${chart_version}" \
  --namespace "${namespace}" \
  --set installCRDs=true \
  --include-crds \
  | ruby -ryaml -e '
      YAML.load_stream($stdin.read).compact.each do |document|
        puts YAML.dump(document) if document["kind"] == "CustomResourceDefinition"
      end
    ' > "${temp_file}"

kubectl apply --server-side --force-conflicts -f "${temp_file}"
echo "External Secrets ${chart_version} CRDs were server-side applied."
