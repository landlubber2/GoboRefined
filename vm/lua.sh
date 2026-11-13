#!/usr/bin/env bash
# Run a line of Lua inside the lab VM user's running desktop. Usage: vm/lua.sh 'return 1+1'
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$here/ssh.sh" "sh /tmp/lab-desktop.sh ${LAB_LOGIN:-lab} '$1'"
