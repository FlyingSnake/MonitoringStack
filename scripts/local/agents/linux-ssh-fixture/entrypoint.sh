#!/bin/sh
set -eu

if [ -r /run/fixture/authorized_keys ]; then
  install -d -m 0700 -o alloytest -g alloytest /home/alloytest/.ssh
  install -m 0600 -o alloytest -g alloytest /run/fixture/authorized_keys /home/alloytest/.ssh/authorized_keys
fi

exec "$@"
