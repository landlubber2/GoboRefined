#!/usr/bin/env bash
# SSH into the lab VM (needs NAT port forward 2222 -> guest 22 and vm/ssh key installed in the guest).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec ssh -i "$here/ssh/id_ed25519" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ConnectTimeout=8 -o BatchMode=yes root@127.0.0.1 "$@"
