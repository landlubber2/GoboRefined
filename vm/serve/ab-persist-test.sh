#!/bin/bash
# Lab only (0.8 A/B test plan, point 2): make system changes that must survive reboots and updates.
# Run as root on an installed GoboRefined 0.8:  wget -qO- http://10.0.2.2:8766/ab-persist-test.sh | bash
#   ... check   -> prints the state (run after reboots / updates)
set -e
mode=${1:-make}
if [ "$mode" = make ]
then
   # 1. a second user (password hashed like gobo-install does; AddUser's passwd needs a terminal)
   id second > /dev/null 2>&1 || AddUser -f "Second User" -p '!' --skel second > /dev/null
   usermod -p "$(printf '%s' 'second-lab-pw' | openssl passwd -6 -stdin)" second
   # 2. a changed settings file in /System/Settings
   grep -q abtest-host /System/Settings/hosts || echo "10.0.2.99 abtest-host" >> /System/Settings/hosts
   # 3. a hand-installed program with a shared library (ldconfig cache test)
   P=/Programs/TinyAB/1.0
   mkdir -p $P/bin $P/lib $P/Resources
   printf 'int tinyab_answer(void) { return 42; }\n' > /tmp/tinyab.c
   if command -v gcc > /dev/null
   then gcc -shared -fPIC -Wl,-soname,libtinyab.so.1 -o $P/lib/libtinyab.so.1.0 /tmp/tinyab.c
        ln -sfn libtinyab.so.1.0 $P/lib/libtinyab.so.1
   fi
   printf '#!/bin/sh\necho "TinyAB 1.0 (hand-installed in the A/B persistence test)"\n' > $P/bin/tiny-ab
   chmod 755 $P/bin/tiny-ab
   echo "Lab test program (hand-installed)." > $P/Resources/Description
   ln -sfn 1.0 /Programs/TinyAB/Current
   SymlinkProgram TinyAB > /dev/null
   ldconfig
   echo "made"
fi
echo "--- state"
echo "version:    $(cat /System/Slot/gobo-slot.env 2>/dev/null | grep -a slot_version)"
echo "slot:       $(tr ' ' '\n' < /proc/cmdline | grep -E '^gobo\.(slot|system-changes)=' | tr '\n' ' ')"
echo "user:       $(id second 2>&1)"
echo "hosts:      $(grep abtest-host /System/Settings/hosts || echo missing)"
echo "tiny-ab:    $(tiny-ab 2>&1)"
echo "ldconfig:   $(ldconfig -p | grep -c libtinyab) entries for libtinyab"
echo "hello-ab:   $(hello-ab 2>&1 || true)"
echo "coreutils:  $(grep -c 'A/B update test change' /Programs/CoreUtils/Current/Resources/Description) test line(s)"
echo "look:       $(cat /Users/lab/.config/awesome/look-version 2>/dev/null || echo none)"
echo "upper:      $(du -sh /System/Data/System-Overlay/upper | cut -f1)"
