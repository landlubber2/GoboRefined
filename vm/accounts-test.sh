#!/usr/bin/env bash
# Lab test (0.9.1): the three kinds of accounts and the security pieces around them.
#   vm/accounts-test.sh            helper checks (needs SSH into the VM as root, the 0.9.1 files
#                                  installed, and the standard user "tester" of vm/settings-test.sh)
#   vm/accounts-test.sh session    checks inside the running desktop of the Simple user "kid"
#                                  (log kid in first; see HANDOFF.md 0.9.1)
#   vm/accounts-test.sh remove     remove "kid" (with home) and the test files
# The lab password goes into the VM through a pipe into a root-only file (never printed); the test
# users' passwords are made up in the VM (/tmp/acctest.*), never shown.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S() { "$here/ssh.sh" "$1"; }
pass=0 fail=0
ok() { if echo "$2" | grep -q -- "$3"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1: got [$2], want /$3/"; fail=$((fail+1)); fi; }
no() { if echo "$2" | grep -q -- "$3"; then echo "FAIL $1: got [$2], must not match /$3/"; fail=$((fail+1)); else echo "PASS $1"; pass=$((pass+1)); fi; }
HELPER=/System/Index/bin/gobo-settings-helper

if [ "${1:-}" != session ] && [ "${1:-}" != remove ]; then
   sed -n 's/^USER_PASSWORD=//p' "$here/serve/lab-answers.env" | sed -e "s/^['\"]//" -e "s/['\"]\$//" | tr -d '\r\n' |
      S 'd=$(mktemp -d /tmp/acctest.XXXXXX); chmod 755 $d; cat > $d/pw; chown lab $d/pw; chmod 600 $d/pw
         printf "#!/bin/sh\ncat $d/pw\n" > $d/askpass; chown lab $d/askpass; chmod 700 $d/askpass
         head -c 3 /dev/urandom | od -An -tx1 | tr -d " \n" > $d/kidpw; chmod 644 $d/kidpw
         printf "#!/bin/sh\ncat $d/kidpw\n" > $d/kidask; chmod 755 $d/kidask
         head -c 12 /dev/urandom | od -An -tx1 | tr -d " \n" > $d/tpw; chmod 644 $d/tpw
         echo $d > /tmp/acctest.dir'
fi
D=$(S 'cat /tmp/acctest.dir 2>/dev/null')
# H args...: the helper as lab (administrator), through sudo -A as the Settings app calls it
H() { S "cd /tmp; su lab -c 'SUDO_ASKPASS=$D/askpass sudo -A $HELPER $*' 2>&1"; }
HIN() { local input="$1"; shift; S "cd /tmp; ( $input ) | su lab -c 'SUDO_ASKPASS=$D/askpass sudo -A $HELPER $*' 2>&1"; }
# AS login args...: the helper as another user through sudo with that user's password (askpass)
AS() { local who="$1" ask="$2"; shift 2; S "cd /tmp; su $who -c 'SUDO_ASKPASS=$ask sudo -A $HELPER $*' < /dev/null 2>&1"; }
# CALLER login args...: the helper as root with SUDO_USER=login (its own administrator check, without sudo)
CALLER() { local who="$1"; shift; S "cd /tmp; SUDO_USER=$who $HELPER $* < /dev/null 2>&1"; }

if [ "${1:-}" = remove ]; then
   # 0.10.8: leftovers OWNED by kid in /tmp go with the account; a file that only has kid's name stays
   S 'su kid -s /bin/sh -c "touch /tmp/.pcmanfm-socket--9-kid"; touch /tmp/.acctest-decoy-kid' > /dev/null
   ok "remove kid with home" "$(H remove-user kid delete-home; S 'grep -c ^kid: /System/Settings/passwd; ls -d /Users/kid 2>&1')" "No such file"
   ok "kid's own file in /tmp removed, a root file named like kid kept" "$(S 'ls -a /tmp | grep -c -x .pcmanfm-socket--9-kid; ls /tmp/.acctest-decoy-kid; rm -f /tmp/.acctest-decoy-kid' | tr '\n' ' ')" "^0 .*acctest-decoy-kid"
   no "login list without kid" "$(S 'grep ^white= /System/Settings/lxdm/lxdm.conf | tr " =" "\n\n" | grep -x kid')" "kid"
   ok "kid out of group simple" "$(S 'grep ^simple: /System/Settings/group')" "^simple:[^:]*:970:$"
   ok "kid's program list removed" "$(S 'ls /Data/Variable/lib/gobo-settings/simple-apps/kid 2>&1')" "No such file"
   S "rm -rf $D /tmp/acctest.dir"
   echo "passed $pass, failed $fail"; exit
fi

if [ "${1:-}" = session ]; then
   L() { S "sh /tmp/lab-desktop.sh kid '$1'"; }
   S 'wget -qO /tmp/lab-desktop.sh http://10.0.2.2:8766/lab-desktop.sh'
   ok "session: kid's desktop knows it is Simple" "$(L 'return tostring(spin_simple.is_simple)')" "true"
   items=$(L 'local t = {} for _, i in ipairs(spin_debug.mainmenu.items) do table.insert(t, i.label and i.label.text or "?") end return table.concat(t, "|")')
   no "session: no Terminal in the menu" "$items" "Terminal"
   no "session: no Desktop tools in the menu" "$items" "Desktop"
   ok "session: menu has Settings and Power" "$items" "Settings.*Power"
   # 0.9.5: the desktop's right-click menu: no Terminal, the rest is there
   ditems=$(L 'local t = {} for _, i in ipairs(spin_debug.desktopmenu.items) do table.insert(t, i.label and i.label.text or "?") end return table.concat(t, "|")')
   no "session: no Terminal in the desktop menu" "$ditems" "Terminal"
   ok "session: desktop menu entries" "$ditems" "Search applications...|New|Window layout|.* mode|Personalization...|Displays...|Detect displays"
   apps=$(L 'return table.concat(spin_launcher.app_names(), "|")')
   ok "session: search lists the allowed programs" "$apps" "Firefox"
   no "session: search has no terminal" "$apps" "[Tt]erminal\|URxvt\|XTerm\|Htop\|GParted\|Vim"
   ok "session: search for urxvt finds nothing to run" "$(L 'local m = spin_launcher.matches_for("urxvt") return "n=" .. #m .. " " .. table.concat(m, "|")')" "\"n=0 "
   keys=$(L 'local n = 0 for _, k in ipairs(root.keys()) do if k.key == "Return" and #k.modifiers == 1 and k.modifiers[1] == "Mod4" then n = n + 1 end end return "winreturn=" .. n')
   ok "session: Win+Enter (terminal) not bound" "$keys" "winreturn=0"
   keys=$(L 'local n = 0 for _, k in ipairs(root.keys()) do if k.key == "Escape" then n = n + 1 end end return "esc=" .. n')
   no "session: Win+Escape still bound" "$keys" "esc=0"
   # 0.9.6: the frequently-used panel works for Simple accounts; files and folders cannot be pinned;
   # their hotkeys file is ignored (no Hotkeys tile; a file planted by hand changes nothing)
   ok "session: frequently used panel opens with the menu" "$(L 'local sp = require("spin.startpanel") local was = sp.enabled() sp.set_enabled(true) spin_debug.mainmenu:show() local v = spin_debug.startpanel ~= nil and spin_debug.startpanel.visible spin_debug.mainmenu:hide() sp.set_enabled(was) return "panel=" .. tostring(v)')" "panel=true"
   ok "session: no file pins for Simple" "$(S 'su kid -c "gobo-pin-to-start /Users/kid/Desktop" > /dev/null 2>&1; echo pin=$?')" "pin=1"
   # 0.10.6: no start menu editor and no "Install" for AppImages in a Simple account
   ok "session: no start menu editor for Simple" "$(S 'su kid -c "gobo-menu-editor" > /dev/null 2>&1; echo editor=$?')" "editor=1"
   ok "session: no Install for Simple" "$(S 'su kid -c "gobo-install-app --offer /Users/kid/Downloads/x.AppImage"; echo rc=$?' | tr '\n' ' ')" "false rc=1"
   ok "session: own hotkeys ignored for Simple" "$(S 'su kid -c "mkdir -p ~/.config/goborefined && printf \"key\\tclipboard\\tMod4+x\\n\" > ~/.config/goborefined/hotkeys"'; L 'spin_hotkeys_reload() local n = 0 for _, k in ipairs(root.keys()) do if k.key == "x" then n = n + 1 end end return "x=" .. n')" "x=0"
   S 'rm -f /Users/kid/.config/goborefined/hotkeys'
   # the file manager: "/" and "/Programs" refused, a window starts at home
   S "pkill -u kid -x pcmanfm -f -- '--no-desktop' 2>/dev/null; pid=\$(pgrep -u kid -x awesome | head -n 1); disp=\$(tr '\\0' '\\n' < /proc/\$pid/environ | sed -n 's/^DISPLAY=//p'); su kid -c \"DISPLAY=\$disp pcmanfm /Programs > /dev/null 2>&1 &\"; sleep 4"
   wins=$(L 'local t = {} for _, c in ipairs(client.get()) do table.insert(t, (c.class or "?") .. ":" .. (c.name or "?")) end return table.concat(t, "|")')
   ok "session: PCManFM opened at home instead of /Programs" "$wins" "Pcmanfm:kid"
   no "session: no PCManFM window on /Programs" "$wins" "Pcmanfm:Programs"
   echo "passed $pass, failed $fail"; exit
fi

### kinds of accounts ######################################################################
ok "groups simple and remote exist (fixed ids)" "$(S 'grep -E "^(simple|remote):" /System/Settings/group | cut -d: -f1,3 | tr "\n" " "')" "simple:970 remote:971"
ok "refused: Simple password of 3 characters" "$(HIN "printf 'Kid\nabc\n'" add-user kid simple)" "too short: at least 4"
ok "refused: administrator password of 6 characters" "$(HIN "printf 'Adm\nabcdef\n'" add-user adm6 admin)" "too short: at least 8"
ok "refused: standard password of 7 characters" "$(HIN "printf 'Std\nabcdefg\n'" add-user std7 standard)" "too short: at least 8"
ok "refused: unknown kind" "$(HIN "printf 'X\nabcdefgh\n'" add-user xkind superuser)" "kind must be"
# 0.10.8: a leftover of an earlier kid (owned by a uid nobody has) must not block the new kid's file manager
S 'touch /Data/Variable/tmp/.pcmanfm-socket--0-kid && chown 59998:100 /Data/Variable/tmp/.pcmanfm-socket--0-kid' > /dev/null
ok "add a Simple account (kid, larger text)" "$(HIN "printf 'Kid Test\n'; cat $D/kidpw; echo" add-user kid simple large-text)" "added kid"
ok "orphaned leftover of an earlier kid removed" "$(S 'ls -a /Data/Variable/tmp | grep -c -x .pcmanfm-socket--0-kid')" "^0$"
ok "login list has kid, lxdm list on" "$(S 'grep -E "^(white|disable)=" /System/Settings/lxdm/lxdm.conf | tr "\n" " "')" "disable=0 .*white=.*kid"
ok "new Simple account: USB on, no internal disks, not in disk" "$(S 'id -Gn kid | tr " " "\n" | grep -x -e gobo-usb -e "gobo-disk-.*" -e disk | tr "\n" " "')" "^gobo-usb $"
ok "kid is in simple, not in sys" "$(S 'id -Gn kid | tr " " "\n" | grep -x -e simple -e sys | tr "\n" " "')" "^simple $"
ok "kid's home is private (700)" "$(S 'stat -c %a /Users/kid')" "^700$"
ok "kid: larger text marker" "$(S 'ls /Users/kid/.config/goborefined/')" "large-text"
ok "kid: file manager places (no file system, Trash on)" "$(S 'grep -E "^places_(root|trash)=" /Users/kid/.config/libfm/libfm.conf | tr "\n" " "')" "places_root=0 places_trash=1"
ok "kid: side pane bookmarks = standard folders" "$(S 'cut -d" " -f2 /Users/kid/.config/gtk-3.0/bookmarks | tr "\n" " "')" "Documents Downloads Pictures Music Videos"
ok "all homes of people are private" "$(S 'stat -c "%a %U %n" /Users/* | grep -v " root " | grep -v -c "^700 "')" "^0$"
ok "kid cannot list another home" "$(S "su kid -c 'ls /Users/lab' 2>&1")" "Permission denied"
ok "tester (standard) cannot list another home" "$(S "su tester -c 'ls /Users/lab' 2>&1")" "Permission denied"
ok "sudo -n true fails for kid (Simple)" "$(S "su kid -c 'sudo -n true' 2>&1; echo rc=\$?")" "rc=1"
ok "sudo -n true fails for tester (standard)" "$(S "su tester -c 'sudo -n true' 2>&1; echo rc=\$?")" "rc=1"
ok "sudo with kid's password: not allowed" "$(S "cat $D/kidpw | su kid -c 'sudo -S -p \"\" true' 2>&1")" "not allowed\|not in the sudoers"
ok "sudo -l for kid: only own-password, report, power, Wi-Fi switch" "$(S "cat $D/kidpw | su kid -c 'sudo -S -p \"\" -l' 2>&1 | grep -c '/System/Index/bin/'")" "^[34]$"
ok "kid may change own password (4+ characters)" "$(S "printf 'k1d2\n' | su kid -c 'SUDO_ASKPASS=$D/kidask sudo -A $HELPER own-password' 2>&1; echo rc=\$?")" "rc=0"
S "printf k1d2 > $D/kidpw"
ok "kid: own password of 3 characters refused" "$(S "printf 'k1d\n' | su kid -c 'SUDO_ASKPASS=$D/kidask sudo -A $HELPER own-password' 2>&1")" "too short"

### every administrative sub-command refused for standard and Simple #######################
ADMIN_CMDS=("set-password lab" "add-user zz standard" "remove-user lab keep-home" "set-kind lab simple" "set-admin lab no"
            "simple-apps kid" "autologin off" "autologin-status" "ssh on" "remote-users" "update-status"
            "update-install /tmp/x.update" "update-rollback" "bluetooth-service start" "bluetooth-boot off"
            "hotspot-set" "hotspot on" "firewall off")
for c in "${ADMIN_CMDS[@]}"; do
   ok "sudo refuses kid: $c" "$(AS kid $D/kidask $c)" "not allowed\|may not run"
done
S "printf '#!/bin/sh\ncat $D/tpw\n' > $D/task; chmod 755 $D/task"
# tester's password from settings-test.sh is unknown here: set a new one as lab first
HIN "cat $D/tpw; echo" set-password tester > /dev/null
for c in "${ADMIN_CMDS[@]}"; do
   ok "sudo refuses tester: $c" "$(AS tester $D/task $c)" "not allowed\|may not run"
done
# the helper's own check (as if sudo let them through)
for c in "set-password lab" "add-user zz standard" "remove-user lab keep-home" "set-kind lab simple" "set-admin lab no" \
         "simple-apps kid" "autologin off" "autologin-status" "ssh on" "remote-users" "update-status" "update-rollback" \
         "bluetooth-service start" "bluetooth-boot off" "hotspot-set" "hotspot on" "firewall off"; do
   ok "helper itself refuses kid: $c" "$(CALLER kid $c)" "only an administrator"
done
for c in boot-ssh boot-bluetooth boot-bluetooth-name; do
   ok "helper itself refuses kid: $c" "$(CALLER kid $c)" "boot scripts"
done

### changing the kind ######################################################################
ok "kid -> standard" "$(H set-kind kid standard; S 'id -Gn kid | tr " " "\n" | grep -x -c -e simple -e sys')" "^0$"
ok "kid standard: file system back in the side pane" "$(S 'grep ^places_root= /Users/kid/.config/libfm/libfm.conf')" "places_root=1"
ok "kid -> administrator" "$(H set-kind kid admin; S 'id -Gn kid | tr " " "\n" | grep -x -e sys -e remote -e simple | sort | tr "\n" " "')" "^remote sys $"
ok "kid -> simple (leaves sys and remote)" "$(H set-kind kid simple; S 'id -Gn kid | tr " " "\n" | grep -x -e sys -e remote -e simple | tr "\n" " "')" "^simple $"
ok "refused: lab makes itself Simple" "$(H set-kind lab simple)" "your own administrator"
ok "refused: program list with a bad name" "$(HIN "printf 'firefox.desktop\n../x.desktop\n'" simple-apps kid)" "not a program name"
ok "program list saved (readable, root-owned)" "$(HIN "printf 'firefox.desktop\npcmanfm.desktop\nl3afpad.desktop\n'" simple-apps kid; S 'stat -c "%a %U" /Data/Variable/lib/gobo-settings/simple-apps/kid')" "644 root"

### 0.10.2: disks and USB drives per account ###############################################
ok "nobody in the group disk" "$(S 'grep ^disk: /System/Settings/group')" "^disk:[^:]*:8:$"
ok "AddUser no longer adds disk" "$(S 'grep -c "^usermod -g users -G .*disk" $(readlink -f /System/Index/bin/AddUser)')" "^0$"
ok "group gobo-usb (969); udevil only for it" "$(S '{ grep ^gobo-usb: /System/Settings/group | cut -d: -f1,3; grep ^allowed_groups /System/Settings/udevil/udevil.conf; } | tr "\n" " "')" "gobo-usb:969 allowed_groups = gobo-usb"
ok "NTFS helper of 0.10.2 installed" "$(S 'grep -c "remount,rw" /System/Index/sbin/mount.ntfs')" "^1$"
ok "lab and tester always in gobo-usb" "$(S 'for u in lab tester; do id -Gn $u | tr " " "\n" | grep -x gobo-usb; done | wc -l')" "^2$"
ok "refused: USB switch for a standard account" "$(HIN "printf 'usb off\n'" disk-access tester)" "only Simple accounts"
ok "refused: a line the helper does not know" "$(HIN "printf 'usb maybe\n'" disk-access kid)" "not understood"
ok "refused: unknown disk" "$(HIN "printf 'abcdef on\n'" disk-access kid)" "no such disk"
ok "refused for kid (sudo): disk-access" "$(AS kid $D/kidask disk-access lab)" "not allowed\|may not run"
ok "refused for tester (sudo): disk-access" "$(AS tester $D/task disk-access kid)" "not allowed\|may not run"
ok "helper itself refuses kid: disk-access" "$(CALLER kid disk-access lab)" "only an administrator"
ok "helper itself refuses kid: boot-disks" "$(CALLER kid boot-disks)" "boot scripts"
ok "kid: USB off" "$(HIN "printf 'usb off\n'" disk-access kid; S 'id -Gn kid | tr " " "\n" | grep -c -x gobo-usb')" "^0$"
if S 'test -b /dev/sdc1 && ! grep -q "^[^ ]*sdc1 " /proc/mounts'; then
   ok "kid with USB off cannot mount a USB stick" "$(S "cd /tmp; su kid -c 'udevil mount /dev/sdc1' 2>&1")" "not in allowed groups"
   HIN "printf 'usb on\n'" disk-access kid > /dev/null
   ok "kid with USB on mounts it" "$(S "cd /tmp; su kid -c 'udevil mount /dev/sdc1' 2>&1; su kid -c 'udevil umount /dev/sdc1' 2>&1")" "Mounted"
else
   HIN "printf 'usb on\n'" disk-access kid > /dev/null
   echo "(no unmounted USB stick sdc1: USB mount checks skipped)"
fi
ok "kid: USB on again" "$(S 'id -Gn kid | tr " " "\n" | grep -c -x gobo-usb')" "^1$"
disks=$(S 'cut -f1,3 /Data/Variable/run/gobo-disks.list 2>/dev/null | tr "\t\n" ": "')
if [ -n "$disks" ]; then
   for dk in $disks; do
      id=${dk%%:*} name=${dk#*:}
      ok "disk $name: lab (administrator) is a member" "$(S "id -Gn lab | tr ' ' '\n' | grep -c -x gobo-disk-$id")" "^1$"
      ok "disk $name: refused to take it from lab" "$(HIN "printf '$id off\n'" disk-access lab)" "administrators always"
      ok "disk $name: kid off -> cannot open" "$(HIN "printf '$id off\n'" disk-access kid; S "su kid -c 'ls /Mount/Disks/$name' 2>&1")" "Permission denied"
      ok "disk $name: kid on -> can open" "$(HIN "printf '$id on\n'" disk-access kid; S "su kid -c 'ls -d /Mount/Disks/$name/.' 2>&1")" "/Mount/Disks/$name/.$"
      ok "disk $name: tester off -> cannot open" "$(HIN "printf '$id off\n'" disk-access tester; S "su tester -c 'ls /Mount/Disks/$name' 2>&1")" "Permission denied"
      ok "disk $name: tester on -> can open" "$(HIN "printf '$id on\n'" disk-access tester; S "su tester -c 'ls -d /Mount/Disks/$name/.' 2>&1")" "/Mount/Disks/$name/.$"
      HIN "printf '$id off\n'" disk-access kid > /dev/null
   done
else
   echo "(no other internal disks: per-disk checks skipped)"
fi

### automatic login, remote access, firewall ###############################################
ok "refused: automatic login of an administrator without confirmation" "$(H autologin lab)" "needs the confirmation"
ok "automatic login of an administrator, confirmed" "$(H autologin lab confirmed; H autologin-status)" "^lab$"
ok "automatic login of kid (Simple)" "$(H autologin kid; H autologin-status)" "^kid$"
ok "automatic login off" "$(H autologin off; H autologin-status)" "^off$"
ok "who may connect: lab only" "$(HIN "printf 'lab\n'" remote-users; S 'grep ^remote: /System/Settings/group')" "^remote:[^:]*:971:lab$"
ok "refused: a Simple account may not connect" "$(HIN "printf 'lab\nkid\n'" remote-users)" "Simple account"
ok "firewall on and loaded" "$(H firewall-status)" "^on active"
ok "firewall off" "$(H firewall off)" "off inactive"
ok "firewall on again" "$(H firewall on)" "on active"
ok "SSH port closed while remote access is off" "$(S 'iptables -S GOBO_OPEN | grep -c "dport 22"')" "^0$"
# (the lab's own sshd holds port 22, so the helper's sshd cannot start here: its options are
# checked with sshd -T, the port with the firewall)
ok "remote access on: port 22 open in the firewall" "$(H ssh on; S 'iptables -S GOBO_OPEN | grep -c "dport 22"')" "^1$"
ok "sshd accepts the helper's options" "$(S "grep -c 'MaxAuthTries=3 -o LoginGraceTime=30 -o PermitEmptyPasswords=no' $HELPER | tr '\n' ' ';\$(command -v sshd) -T -o PermitRootLogin=no -o AllowGroups=remote -o MaxAuthTries=3 -o LoginGraceTime=30 -o PermitEmptyPasswords=no 2>&1 | grep -E '^(allowgroups|maxauthtries|logingracetime|permitemptypasswords|permitrootlogin) ' | sort | tr '\n' ' '")" "^1 allowgroups remote logingracetime 30 maxauthtries 3 permitemptypasswords no permitrootlogin no"
ok "remote access off: port closed again" "$(H ssh off; S 'iptables -S GOBO_OPEN | grep -c "dport 22"')" "^0$"
ok "sudo defaults: env_reset, secure_path, 5 minutes" "$(S 'grep -E "^Defaults" /Programs/Sudo/Settings/sudoers | tr "\n" " "')" "env_reset.*secure_path.*timestamp_timeout=5"
ok "kernel settings applied" "$(S 'sysctl -n kernel.kptr_restrict fs.protected_symlinks net.ipv4.conf.all.rp_filter kernel.yama.ptrace_scope kernel.dmesg_restrict | tr "\n" " "')" "^1 1 1 1 1 $"
echo "(kid kept for the session test; remove with: vm/accounts-test.sh remove)"
echo "passed $pass, failed $fail"
