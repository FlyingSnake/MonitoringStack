#!/usr/bin/env bash
set -euo pipefail

template_name="${1:?usage: scripts/local/awx-job.sh <job-template-name>}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/lib.sh"

require_kind_cluster monitoring-local
kubectl -n awx get service monitoring-awx-service >/dev/null

port="${AWX_LOCAL_PORT:-18051}"
kubectl -n awx port-forward service/monitoring-awx-service "${port}:80" >/dev/null 2>&1 &
forward_pid=$!
cleanup() { kill "${forward_pid}" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 30); do
  curl --silent --fail "http://127.0.0.1:${port}/api/v2/ping/" >/dev/null 2>&1 && break
  sleep 1
done
curl --silent --fail "http://127.0.0.1:${port}/api/v2/ping/" >/dev/null

password="$(kubectl -n awx get secret awx-admin -o jsonpath='{.data.password}' | base64 -d)"
template_id="$(curl --silent --show-error --fail --user "admin:${password}" --get \
  --data-urlencode "name=${template_name}" \
  "http://127.0.0.1:${port}/api/v2/job_templates/" | jq -r '.results[0].id // empty')"
if [[ -z "${template_id}" ]]; then
  echo "AWX Job Template was not found: ${template_name}" >&2
  exit 1
fi

job_id="$(curl --silent --show-error --fail --user "admin:${password}" \
  -H 'Content-Type: application/json' --data '{}' \
  "http://127.0.0.1:${port}/api/v2/job_templates/${template_id}/launch/" | jq -r '.id')"
echo "AWX Job launched: template=${template_name}, id=${job_id}"

for _ in $(seq 1 120); do
  status="$(curl --silent --show-error --fail --user "admin:${password}" "http://127.0.0.1:${port}/api/v2/jobs/${job_id}/" | jq -r '.status')"
  case "${status}" in
    successful)
      echo "AWX Job succeeded: ${job_id}"
      exit 0
      ;;
    failed|error|canceled)
      echo "AWX Job failed: ${job_id} (${status})" >&2
      exit 1
      ;;
  esac
  sleep 5
done

echo "AWX Job timed out: ${job_id}" >&2
exit 1
