#!/usr/bin/env bash
set -euo pipefail

fixture_name="monitoring-linux-alloy-fixture"
docker exec "${fixture_name}" systemctl is-active alloy | grep -qx active
docker exec "${fixture_name}" stat -c '%a %U %G' /etc/alloy/credentials/environment | grep -qx '640 root alloy'
docker exec "${fixture_name}" test -s /etc/alloy/credentials/environment
docker exec "${fixture_name}" journalctl -u alloy --since '5 minutes ago' --no-pager | grep -Eqi 'error|failed' && {
  echo "Alloy service reported an error." >&2
  exit 1
} || true
echo "Linux fixture Alloy service and credential file permissions were verified."
