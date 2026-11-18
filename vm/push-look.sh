#!/usr/bin/env bash
# Push look/gobo11 to the lab VM's user, check the config, and reload the desktop.
# Usage: vm/push-look.sh [login]      (needs vm/serve.js running and SSH into the VM)
set -e
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
login="${1:-lab}"
(cd "$here/../look" && tar czf "$here/serve/gobo11.tgz" gobo11)
"$here/ssh.sh" "cd /tmp && rm -rf gobo11 && wget -qO gobo11.tgz http://10.0.2.2:8766/gobo11.tgz && tar xzf gobo11.tgz 2>/dev/null \
  && wget -qO lab-desktop.sh http://10.0.2.2:8766/lab-desktop.sh \
  && sh gobo11/apply.sh /Users/$login > /dev/null && chown -R $login:users /Users/$login/.config /Users/$login/.local /Users/$login/.xinitrc /Users/$login/.Xresources /Users/$login/.urxvt \
     /Users/$login/Desktop /Users/$login/Documents /Users/$login/Downloads /Users/$login/Music /Users/$login/Pictures /Users/$login/Videos \
  && su $login -c 'awesome -k' 2>&1 | tail -n 3 \
  && sh lab-desktop.sh $login 'awesome.restart()'"
