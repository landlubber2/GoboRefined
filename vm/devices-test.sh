#!/usr/bin/env bash
# Lab test (0.9.2): the Device Manager's classification, the package check and the helper's
# refusals. Needs SSH into the VM as root and the 0.9.2 files installed.
#   vm/devices-test.sh
# Part 1 feeds devices.lua a made-up laptop (vm/devices-fixture.txt: the scan's own text format
# with "|" where the scan prints a tab): missing Wi-Fi and SOF sound firmware (the 0.8.3 laptop
# case), a network card whose driver is not loaded, a USB gadget nothing knows, a Wi-Fi stick in
# "driver CD" mode, a blocked radio, a card reader that needs no driver, a healthy Wi-Fi card.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S() { "$here/ssh.sh" "$1"; }
pass=0 fail=0
ok() { if echo "$2" | grep -q -- "$3"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1: got [$2], want /$3/"; fail=$((fail+1)); fi; }
L=/Programs/GoboSpin/Current/share/gobo-settings/devices.lua
HELPER=/System/Index/bin/gobo-settings-helper
FIX="GOBO_DEVICES_SCAN='cat /tmp/devices-fixture.tsv #'"
tr '|' '\t' < "$here/devices-fixture.txt" | S 'cat > /tmp/devices-fixture.tsv'
st=$(S "$FIX lua $L --states")
ok "graphics with a driver: working" "$st" "^pci 0000:00:02.0 display ok$"
ok "Wi-Fi whose firmware is missing" "$st" "^pci 0000:00:14.3 wifi firmware$"
ok "SOF sound without firmware" "$st" "^pci 0000:00:1f.3 sound firmware$"
ok "network card: driver on the system, not active" "$st" "^pci 0000:02:00.0 network inactive$"
ok "card reader without a driver is not a problem" "$st" "^pci 0000:03:00.0 system info$"
ok "healthy Wi-Fi card" "$st" "^pci 0000:04:00.0 wifi ok$"
ok "Wi-Fi stick in driver-CD mode" "$st" "^usb 1-3 storage inactive$"
ok "USB gadget nothing knows: no driver" "$st" "^usb 1-4 other nodriver$"
ok "blocked Bluetooth radio: switched off" "$st" "^usb 1-7 bluetooth disabled$"
ok "five devices need attention" "$st" "^problems 5$"
tx=$(S "$FIX lua $L --text")
ok "the firmware file is named" "$tx" "Firmware asked for: iwlwifi-QuZ-a0-test-999.ucode (MISSING)"
ok "driver-CD mode is explained" "$tx" "driver CD"
ok "the module is named for the inactive card" "$tx" "Driver available: r8169"
ok "this VM: no device needs attention" "$(S "lua $L --states | tail -n 1")" "^problems 0$"
ok "lookup URL from IDs only" "$(S "cd /Programs/GoboSpin/Current/share/gobo-settings && lua -e 'D=require(\"devices\") print(D.lookup_url(\"hardware\",\"usb\",\"2357\",\"013F\")) print(D.lookup_url(\"hardware\",\"usb\",\"23/7\",\"013f\")) print(D.search_url(\"a b&c=d\"))'" | tr '\n' ' ')" "^https://linux-hardware.org/?id=usb:2357-013f nil nil"
# helper refusals (as root, so only the argument checks are tested here)
ok "device-start: path tricks refused" "$(S "$HELPER device-start pci ../../etc 2>&1")" "bad device address"
ok "device-start: unknown bus refused" "$(S "$HELPER device-start scsi 0000:00:02.0 2>&1")" "the bus is pci or usb"
ok "device-start: no such device" "$(S "$HELPER device-start pci 0000:7f:1f.7 2>&1")" "no such device"
ok "device-unblock: a device without a radio" "$(S "$HELPER device-unblock pci 0000:00:02.0 2>&1")" "no radio switch"
ok "app-remove: a system program is refused" "$(S "$HELPER app-remove Bash 5.0 2>&1")" "was not installed from a file"
ok "app-install: not a package name" "$(S "touch /tmp/x.update; $HELPER app-install /tmp/x.update 2>&1")" "not a GoboLinux package file name"
# the package check: a real package made here, then ones that must fail
S 'rm -rf /tmp/pk && mkdir -p /tmp/pk/Hello/1.0/bin /tmp/pk/Hello/1.0/Resources && cd /tmp/pk &&
   printf "#!/bin/sh\necho hello\n" > Hello/1.0/bin/hello-gobo && chmod 755 Hello/1.0/bin/hello-gobo &&
   echo x86_64 > Hello/1.0/Resources/Architecture && echo "Glibc >= 2.20" > Hello/1.0/Resources/Dependencies &&
   tar cjf Hello--1.0--x86_64.tar.bz2 Hello && tar cjf Hello--1.0--arm64.tar.bz2 Hello &&
   echo "Glibc >= 9.9" > Hello/1.0/Resources/Dependencies && mv Hello/1.0 Hello/1.1 && tar cjf Hello--1.1--x86_64.tar.bz2 Hello &&
   echo "Glibc >= 2.20" > Hello/1.1/Resources/Dependencies && mv Hello/1.1 Hello/1.2 &&
   chmod 4755 Hello/1.2/bin/hello-gobo && tar cjf Hello--1.2--x86_64.tar.bz2 Hello &&
   mkdir -p Cp/1.0/bin && cp /System/Index/bin/cp Cp/1.0/bin/cp-copy && tar cjf Cp--1.0--x86_64.tar.bz2 Cp'
ok "check: a fitting package" "$(S 'gobo-app-check /tmp/pk/Hello--1.0--x86_64.tar.bz2 | tail -n 1')" "^RESULT compatible$"
ok "check: needs a newer program" "$(S 'gobo-app-check /tmp/pk/Hello--1.1--x86_64.tar.bz2 | tr "\n" " "')" "FAIL needs Glibc 9.9 or newer.*RESULT not compatible"
ok "check: another architecture" "$(S 'gobo-app-check /tmp/pk/Hello--1.0--arm64.tar.bz2 | tr "\n" " "')" "FAIL made for arm64.*RESULT not compatible"
ok "check: setuid file refused" "$(S 'gobo-app-check /tmp/pk/Hello--1.2--x86_64.tar.bz2 | tr "\n" " "')" "FAIL the package has files that would run with root rights"
ok "check: a compiled program of this system fits" "$(S 'gobo-app-check /tmp/pk/Cp--1.0--x86_64.tar.bz2 | tr "\n" " "')" "OK all libraries.*RESULT compatible"
ok "check: not a package" "$(S 'gobo-app-check /tmp/x.update | tail -n 1')" "^RESULT not a package$"
ok "install through the helper" "$(S "$HELPER app-install /tmp/pk/Hello--1.0--x86_64.tar.bz2 2>&1 | tail -n 3")" "INSTALLED-OK Hello 1.0"
ok "the installed command runs" "$(S 'hello-gobo')" "^hello$"
ok "installing it twice is refused" "$(S "$HELPER app-install /tmp/pk/Hello--1.0--x86_64.tar.bz2 2>&1 | tail -n 2")" "already installed"
ok "remove through the helper" "$(S "$HELPER app-remove Hello 1.0 2>&1 | tail -n 1")" "REMOVED-OK Hello 1.0"
ok "the program is gone" "$(S 'ls /Programs/Hello 2>&1 | head -n 1; command -v hello-gobo || echo no-command')" "no-command"
echo "passed $pass, failed $fail"
