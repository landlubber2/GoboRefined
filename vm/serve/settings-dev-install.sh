#!/bin/bash
# Lab helper (0.8.2): install the Settings app, system-disk helper and regulatory.db from the
# host into an INSTALLED system (root overlay), the same files and places as spin/build-iso.sh +
# gobo-make-system put them into the image. Run as root in the VM:
#   wget -qO- http://10.0.2.2:8766/settings-dev-install.sh | bash
# (refresh first on the host: cd spin && tar czf ../vm/serve/spin-extra.tgz firmware settings
#  && tar czf ../vm/serve/ab.tgz ab)
set -e
HOST=http://10.0.2.2:8766
P=/Programs/GoboSpin/Current
d=$(mktemp -d)
cd "$d"
wget -qO- $HOST/spin-extra.tgz | tar xz
wget -qO- $HOST/ab.tgz | tar xz
bash -n settings/gobo-settings-helper; bash -n settings/gobo-report; sh -n ab/gobo-system-disk
for f in settings/*.lua settings/pages/*.lua; do luac -p "$f"; done
install -m 755 settings/gobo-settings settings/gobo-settings-helper settings/gobo-askpass settings/gobo-report ab/gobo-system-disk $P/bin/
mkdir -p $P/share/gobo-settings/pages $P/share/applications $P/lib/firmware $P/lib/udev/rules.d
install -m 644 settings/main.lua settings/common.lua $P/share/gobo-settings/
install -m 644 settings/pages/*.lua $P/share/gobo-settings/pages/
install -m 644 settings/gobo-settings.desktop $P/share/applications/
install -m 644 firmware/wireless-regdb/regulatory.db firmware/wireless-regdb/regulatory.db.p7s $P/lib/firmware/
install -m 644 ab/80-gobo-internal.rules $P/lib/udev/rules.d/
SymlinkProgram GoboSpin > /dev/null 2>&1 || true
for f in gobo-settings gobo-settings-helper gobo-askpass gobo-report gobo-system-disk; do
   [ -e /System/Index/bin/$f ] || ln -sfn $P/bin/$f /System/Index/bin/$f
done
[ -e /System/Index/share/applications/gobo-settings.desktop ] || ln -sfn $P/share/applications/gobo-settings.desktop /System/Index/share/applications/
sudoers=/Programs/Sudo/Settings/sudoers
if ! grep -q 'gobo-settings-helper own-password' $sudoers; then
   cat >> $sudoers <<'SUDOERS'
%users ALL=(root) /System/Index/bin/gobo-settings-helper own-password, /System/Index/bin/gobo-settings-helper report
%users ALL=(root) NOPASSWD: /System/Index/bin/shutdown -r now, /System/Index/bin/shutdown -h now
SUDOERS
fi
visudo -c > /dev/null
bootup=/Programs/BootScripts/Settings/BootScripts/BootUp
grep -q 'gobo-settings-helper boot-ssh' $bootup || cat >> $bootup <<'BOOTUP'

# Added by GoboRefined (0.8.2): remote access (SSH server), only if it was switched on in
# Settings > Remote access (flag on the data partition; off by default).
Exec "Starting remote access (if switched on)..." /System/Index/bin/gobo-settings-helper boot-ssh
BOOTUP
cd /; rm -rf "$d"
ls -l /System/Index/bin/gobo-settings /System/Index/lib/firmware/regulatory.db /System/Index/share/applications/gobo-settings.desktop
echo "settings dev install done"
