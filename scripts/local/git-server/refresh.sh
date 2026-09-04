#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
runtime_dir="${MONITORING_LOCAL_RUNTIME_DIR:-${repo_root}/local}"
repositories_dir="${runtime_dir}/git-server/repositories"
repository_dir="${repositories_dir}/MonitoringStack.git"

if ! git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null; then
  echo "MonitoringStack working tree was not found." >&2
  exit 1
fi

mkdir -p "${repositories_dir}"
if [[ ! -d "${repository_dir}" ]]; then
  git clone --bare "${repo_root}" "${repository_dir}" >/dev/null
else
  git --git-dir="${repository_dir}" fetch --force "${repo_root}" '+refs/heads/*:refs/heads/*' >/dev/null
fi

git --git-dir="${repository_dir}" update-server-info
echo "Local Git repository refreshed from committed refs."
