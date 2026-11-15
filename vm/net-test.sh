#!/usr/bin/env bash
# Lab test (0.8.1) for the network menu's interface re-detection (spin/gobonet_menu.lua).
# The VM has no Wi-Fi, so the test points the module at a fake /sys/class/net tree and a stub
# gobonet_backend (logs its arguments, prints a fake scan), then plugs a "Wi-Fi adapter" in
# and out and checks what the menu would show and which backend commands ran.
#   vm/net-test.sh        (needs SSH into the VM and the lab desktop running)
# Proves the desktop side only; the real driver/scan is for the real PC.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S() { "$here/ssh.sh" "$1"; }
L() { "$here/lua.sh" "$1" | sed 's/^ *string //'; }
pass=0 fail=0
ok() { if echo "$2" | grep -q -- "$3"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1: got [$2], want /$3/"; fail=$((fail+1)); fi; }
no() { if echo "$2" | grep -q -- "$3"; then echo "FAIL $1: got [$2], must not match /$3/"; fail=$((fail+1)); else echo "PASS $1"; pass=$((pass+1)); fi; }

S 'set -e; d=$(mktemp -d /tmp/nettest.XXXXXX); chmod 755 $d; mkdir -p $d/net/eth0 $d/bin
   echo 1 > $d/net/eth0/type; echo 0 > $d/net/eth0/carrier; echo "INTERFACE=eth0" > $d/net/eth0/uevent
   cat > $d/bin/gobonet_backend <<EOF
#!/bin/sh
echo "\$*" >> $d/log
case "\$1" in quick-scan|full-scan) [ -d $d/net/"\$2" ] && printf "Cell 01 - Address: AA:BB:CC:DD:EE:01\n ESSID:\"LabNet\"\n Quality=60/70\nCell 02 - Address: AA:BB:CC:DD:EE:02\n ESSID:\"Neighbour\"\n Quality=20/70\n" ;; esac
exit 0
EOF
   chmod 755 $d/bin/gobonet_backend; touch $d/log; chmod 666 $d/log; echo $d > /tmp/nettest.dir; chmod 644 /tmp/nettest.dir'
D=$(S 'cat /tmp/nettest.dir')
names='local t = {} for _, e in ipairs(W:entries(true)) do table.insert(t, e[1] .. (e[2] and "*" or "")) end return table.concat(t, "|")'

L "M = require(\"spin.gobonet_menu\") M.sysnet = \"$D/net\" M.backend = \"$D/bin/gobonet_backend\" W = M.new() return 1" > /dev/null
sleep 2
e=$(L "$names"); ok "no adapter: wired entry says no cable, not clickable" "$e" "Wired network (eth0): no cable |"
ok "no adapter: says no Wi-Fi adapter" "$e" "No Wi-Fi adapter found"
no "no adapter: no scan ran" "$(S "cat $D/log")" "scan"

S "mkdir $D/net/wlan0 && echo 'DEVTYPE=wlan' > $D/net/wlan0/uevent && echo 1 > $D/net/wlan0/type"
ok "plug in: change detected" "$(L 'return tostring(W:hotplug_check())')" "true"
sleep 2
log=$(S "cat $D/log")
ok "plug in: interface brought up" "$log" "interface-up wlan0"
ok "plug in: background full scan" "$log" "full-scan wlan0"
e=$(L "$names"); ok "plug in: networks listed" "$e" "LabNet\*"
ok "plug in: Rescan offered" "$e" "Rescan\*"
ok "no change: nothing to do" "$(L 'return tostring(W:hotplug_check())')" "false"

S ": > $D/log"
L 'for _, e in ipairs(W:entries(true)) do if e[1]:match("Rescan") then e[2]() end end return 1' > /dev/null
sleep 2
ok "Rescan: full scan on wlan0" "$(S "cat $D/log")" "full-scan wlan0"

S "rm -rf $D/net/wlan0"
ok "unplug: change detected" "$(L 'return tostring(W:hotplug_check())')" "true"
e=$(L "$names"); ok "unplug: no adapter again" "$e" "No Wi-Fi adapter found"

S ": > $D/log; mkdir $D/net/wlan1 && touch $D/net/wlan1/phy80211 && echo 1 > $D/net/wlan1/type"
ok "plug in again (new name): change detected" "$(L 'return tostring(W:hotplug_check())')" "true"
sleep 2
log=$(S "cat $D/log"); ok "plug in again: wlan1 brought up" "$log" "interface-up wlan1"
e=$(L "$names"); ok "plug in again: networks listed" "$e" "LabNet"
ok "plug in again: scanned wlan1" "$(S "cat $D/log")" "quick-scan wlan1"

S "echo 1 > $D/net/eth0/carrier"
e=$(L "$names"); ok "cable in: wired entry clickable" "$e" "Wired network (eth0) \*"

# the real menu, opened through the taskbar icon's fake click, shows and closes
ok "menu opens" "$(L 'W:emit_signal("button::press", 0, 0, 1, {}, {}) return tostring(W:menu() and W:menu().wibox.visible)')" "true"
L 'require("spin.popups").panic() return 1' > /dev/null

L 'M.sysnet = "/sys/class/net" M.backend = "gobonet_backend" W = nil return 1' > /dev/null
S "rm -rf $D /tmp/nettest.dir"
echo "passed $pass, failed $fail"
