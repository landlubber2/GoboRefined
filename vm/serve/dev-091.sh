#!/bin/bash
# Lab helper (0.9.1): put the 0.9.1 work into an INSTALLED 0.8.5 system (root overlay), the same
# files and places as build-iso.sh + gobo-make-system. As root in the VM:
#   wget -qO- http://10.0.2.2:8766/dev-091.sh | bash
# (host first: tar czf vm/serve/dev-091.tgz -C spin settings ab -C ../look gobo11)
set -e
HOST=http://10.0.2.2:8766
P=/Programs/GoboSpin/Current
d=$(mktemp -d)
cd "$d"
wget -qO- $HOST/dev-091.tgz | tar xz
bash -n settings/gobo-settings-helper; bash -n ab/gobo-firewall; bash -n ab/gobo-update
for f in settings/*.lua settings/pages/*.lua gobo11/awesome/spin/*.lua gobo11/awesome/rc.lua; do luac -p "$f"; done
install -m 755 settings/gobo-settings settings/gobo-settings-helper settings/gobo-askpass settings/gobo-report ab/gobo-firewall ab/gobo-update $P/bin/
install -m 644 settings/*.lua settings/simple-apps.default $P/share/gobo-settings/
install -m 644 settings/pages/*.lua $P/share/gobo-settings/pages/
mkdir -p $P/share/gobo-firewall $P/share/gobo-security
install -m 644 ab/firewall.rules $P/share/gobo-firewall/firewall.rules
install -m 644 ab/gobo-sysctl.conf $P/share/gobo-security/sysctl.conf
rm -rf $P/share/gobo11 && cp -r gobo11 $P/share/gobo11
[ -e /System/Index/bin/gobo-firewall ] || ln -sfn $P/bin/gobo-firewall /System/Index/bin/gobo-firewall
for g in simple:970 remote:971
do grep -q "^${g%%:*}:" /System/Settings/group || groupadd -g "${g#*:}" "${g%%:*}"
done
sudoers=/Programs/Sudo/Settings/sudoers
sed -i 's|^%sys ALL=(root) NOPASSWD: /System/Index/bin/shutdown, .*$|%sys ALL=(root) NOPASSWD: /System/Index/bin/shutdown -r now, /System/Index/bin/shutdown -h now|' $sudoers
if grep -q '^Defaults[[:space:]]*!env_reset' $sudoers
then sed -i 's|^Defaults[[:space:]]*!env_reset.*$|# GoboRefined 0.9.1 (stock: "Defaults !env_reset, setenv"):\nDefaults env_reset\nDefaults secure_path="/System/Index/bin:/System/Index/sbin"\nDefaults timestamp_timeout=5\nDefaults:%sys setenv|' $sudoers
fi
visudo -c > /dev/null
cd /; rm -rf "$d"
echo "dev 0.9.1 install done"
