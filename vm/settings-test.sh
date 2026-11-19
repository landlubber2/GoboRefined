#!/usr/bin/env bash
# Lab test (0.8.2) of the Settings app's root helper (gobo-settings-helper), called the way the
# app calls it: as the desktop user lab, through "sudo -A" with an askpass program. The lab
# password goes into the VM through a pipe into a root-only file (never printed); the test
# user's password is made up here and kept in the VM's /tmp only.
#   vm/settings-test.sh        (needs SSH into the VM; vm/serve/settings-dev-install.sh run)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S() { "$here/ssh.sh" "$1"; }
pass=0 fail=0
ok() { if echo "$2" | grep -q -- "$3"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1: got [$2], want /$3/"; fail=$((fail+1)); fi; }

sed -n 's/^USER_PASSWORD=//p' "$here/serve/lab-answers.env" | sed -e "s/^['\"]//" -e "s/['\"]\$//" | tr -d '\r\n' |
   S 'd=$(mktemp -d /tmp/settest.XXXXXX); chown lab $d; chmod 700 $d; cat > $d/pw; chown lab $d/pw; chmod 600 $d/pw
      printf "#!/bin/sh\ncat $d/pw\n" > $d/askpass; chown lab $d/askpass; chmod 700 $d/askpass
      head -c 12 /dev/urandom | od -An -tx1 | tr -d " \n" > $d/testpw; chmod 644 $d/testpw; echo $d > /tmp/settest.dir'
D=$(S 'cat /tmp/settest.dir')
# H args...   : helper as lab (stdin from the rest of the line's here-string is not used)
H() { S "cd /tmp; su lab -c 'SUDO_ASKPASS=$D/askpass sudo -A /System/Index/bin/gobo-settings-helper $*' 2>&1"; }
HIN() { local input="$1"; shift; S "cd /tmp; ( $input ) | su lab -c 'SUDO_ASKPASS=$D/askpass sudo -A /System/Index/bin/gobo-settings-helper $*' 2>&1"; }

if [ "${1:-}" = remove ]; then
   ok "remove tester with home" "$(H remove-user tester delete-home; S 'grep -c ^tester: /System/Settings/passwd; ls -d /Users/tester 2>&1')" "No such file"
   S "rm -rf $D /tmp/settest.dir"
   echo "passed $pass, failed $fail"; exit
fi
ok "refused: bad login" "$(HIN "printf 'X\nabc\n'" add-user Bad.Name standard)" "not a valid login"
ok "refused: remove yourself" "$(H remove-user lab keep-home)" "your own account"
ok "refused: remove root" "$(H remove-user root keep-home)" "system account"
ok "refused: remove a system account" "$(H remove-user bin keep-home)" "system account\|no such user"
ok "refused: demote yourself" "$(H set-admin lab no)" "your own administrator"
ok "refused: unknown sub-command" "$(H frobnicate)" "unknown sub-command"
ok "refused: update file not .update" "$(H update-install /etc/passwd)" "ends in .update"

ok "add a standard user" "$(HIN "printf 'Test Person\n'; cat $D/testpw; echo" add-user tester standard)" "added tester"
ok "tester exists, uid >= 1000" "$(S 'getent passwd tester || grep ^tester: /System/Settings/passwd')" "tester:x:10[0-9][0-9]:100:Test Person"
ok "tester is not in sys" "$(S 'id -Gn tester')" "users"
grep_sys=$(S 'id -Gn tester | tr " " "\n" | grep -x sys || echo none'); ok "tester not administrator" "$grep_sys" "none"
ok "tester home on the data partition with the look" "$(S 'ls /System/Data/Users/tester/.config/awesome/rc.lua && stat -c %U /Users/tester/.config/awesome/rc.lua')" "tester"
ok "tester keyboard line = system layout" "$(S 'grep ^setxkbmap /Users/tester/.xinitrc')" "system_layout"
ok "password hash stored, not in the log" "$(S "grep -c '^tester:\\\$6\\\$' /System/Settings/shadow; grep -c -f $D/testpw /Data/Variable/log/gobo-settings.log")" "^1"
ok "sudo refused for tester" "$(S "cat $D/testpw | su tester -c 'sudo -S -p \"\" true' 2>&1")" "not allowed\|not in the sudoers"
ok "tester may change own password (with their password)" "$(S "cat $D/testpw > $D/testpw-askpass-src; printf '#!/bin/sh\ncat $D/testpw\n' > $D/ta; chmod 755 $D/ta; chmod 755 $D; echo newpass123 | su tester -c 'SUDO_ASKPASS=$D/ta sudo -A /System/Index/bin/gobo-settings-helper own-password' 2>&1; echo rc=\$?")" "rc=0"
S "printf newpass123 > $D/testpw"
ok "tester may NOT add users" "$(S "printf 'a\nb\n' | su tester -c 'SUDO_ASKPASS=$D/ta sudo -A /System/Index/bin/gobo-settings-helper add-user x1 standard' 2>&1")" "not allowed"
ok "make administrator" "$(H set-admin tester yes; S 'id -Gn tester')" "sys"
ok "make standard again" "$(H set-admin tester no; S 'id -Gn tester')" "users"
ok "autologin tester" "$(H autologin tester; H autologin-status)" "^tester$"
ok "autologin off" "$(H autologin off; H autologin-status)" "^off$"
ok "ssh status off by default" "$(H ssh-status)" "^off"
ok "report: kernel messages and slots" "$(H report | grep -c -E '^=== (Last kernel|gobo-update --status)')" "^2$"
ok "update-status" "$(H update-status)" "GoboRefined system versions"   # 0.10: versions A/B (was "slot A")
# 0.8.2 part 2: Bluetooth and hotspot sub-commands (the VM has neither Bluetooth nor Wi-Fi)
ok "refused: bluetooth-boot bad word" "$(H bluetooth-boot maybe)" "say on or off"
ok "bluetooth-boot off -> flag" "$(H bluetooth-boot off; S 'ls /Data/Variable/lib/gobo-settings/')" "bluetooth-off-at-boot"
ok "bluetooth-boot on -> no flag" "$(H bluetooth-boot on; S 'ls /Data/Variable/lib/gobo-settings/ | grep -c bluetooth-off')" "^0$"
ok "bluetooth-service start" "$(H bluetooth-service start; S 'pgrep -x bluetoothd > /dev/null && echo running')" "running"
ok "refused: boot-bluetooth by a user" "$(H boot-bluetooth)" "boot scripts"
ok "refused: boot-bluetooth-name by a user" "$(H boot-bluetooth-name)" "boot scripts"
ok "refused: hotspot password too short" "$(HIN "printf 'Lab Hotspot\nshort\n'" hotspot-set)" "8 to 63"
ok "hotspot-set stores name, key root-only" "$(HIN "printf 'Lab Hotspot\n'; cat $D/testpw; echo" hotspot-set; S 'stat -c %a /Data/Variable/lib/gobo-settings/hotspot.conf; cat /Data/Variable/lib/gobo-settings/hotspot.name')" "600"
ok "hotspot password not in the log or the store" "$(S "grep -c -f $D/testpw /Data/Variable/log/gobo-settings.log /Data/Variable/lib/gobo-settings/hotspot.conf | tr '\n' ' '")" "log:0 .*conf:0"
ok "hotspot on without Wi-Fi: clear refusal" "$(H hotspot on)" "no Wi-Fi adapter found"
ok "hotspot on without Wi-Fi: nothing left running" "$(S 'ls /Data/Variable/run/gobo-hotspot 2>&1; pgrep -c dnsmasq')" "No such file"
ok "refused: standard user may not change the hotspot" "$(S "printf 'a\nbbbbbbbb\n' | su tester -c 'SUDO_ASKPASS=$D/ta sudo -A /System/Index/bin/gobo-settings-helper hotspot-set' 2>&1")" "not allowed"
# 0.8.4: removing a user also removes the user's own group, so the login can be used again
ok "temporary user gets its own group" "$(HIN "printf 'Temp Person\n'; cat $D/testpw; echo" add-user tmpuser standard; S 'grep -c ^tmpuser: /System/Settings/group')" "^1$"
ok "remove user removes its own group" "$(H remove-user tmpuser delete-home; S 'grep -c ^tmpuser: /System/Settings/group; tail -n 1 /Data/Variable/log/gobo-settings.log')" "group removed: tmpuser"
ok "same login can be added again" "$(HIN "printf 'Temp Person\n'; cat $D/testpw; echo" add-user tmpuser standard)" "added tmpuser"
ok "the group is kept while someone else is in it" "$(S 'gpasswd -a tester tmpuser > /dev/null'; H remove-user tmpuser delete-home; S 'grep -c ^tmpuser: /System/Settings/group; groupdel tmpuser')" "^1$"
echo "(tester kept for the login test; remove with: vm/settings-test.sh remove)"
echo "passed $pass, failed $fail"
