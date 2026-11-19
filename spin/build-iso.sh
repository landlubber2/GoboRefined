#!/bin/bash
# Rebuild the GoboRefined ISO (unofficial spin of GoboLinux 017.01), as root on a 017.01 system.
#
# Normally run by build/build.sh (see BUILDING.md), which prepares everything below and sets
# the variables. Every project file is taken from the repository checkout REPO; nothing is
# fetched from the network or from a lab file server.
#
# Variables (defaults in brackets):
#   REPO           the repository checkout                         [the folder above spin/]
#   B              work folder for this image build                [/Data/Build]
#   R              the stock live image tree to add to: an overlay over (or an unpacked copy of)
#                  the stock gobolinux-live.squashfs; it is changed in place   [$B/rootfs]
#   PROGRAMS_FROM  root of the tree holding the built /Programs/<Name> (build/build.sh: its
#                  build root)                                     [empty = this system's /]
#   ISO            the stock GoboLinux-017.01 ISO (file or device) [/dev/sr0]
#   XORRISO        GNU xorriso binary                              [$B/xorriso-inst/bin/xorriso]
#   SIGNING_KEY    private key for the .update file, a copy in memory (/dev/shm); DELETED when
#                  this script ends                                [/dev/shm/gobo-update-signing.pem]
#   PUBKEY         its public key, embedded in the image           [$REPO/spin/ab/update-signing.pub.pem]
#   VERSION        [0.10]
# Programs expected under $PROGRAMS_FROM/Programs: the EXTRA and MODULES lists below, built
# with spin/build-programs.sh.
#
# Writes $B/GoboRefined-$VERSION.iso and GoboRefined-$VERSION.update (the pristine system as a
# signed squashfs, for gobo-update). Needs about 13 GB free in $B.
set -e
B=${B:-/Data/Build}
R=${R:-$B/rootfs}
REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
PROGRAMS_FROM=${PROGRAMS_FROM:-}
ISO=${ISO:-/dev/sr0}
XORRISO=${XORRISO:-$B/xorriso-inst/bin/xorriso}
VERSION=${VERSION:-0.10}
SIGNING_KEY=${SIGNING_KEY:-/dev/shm/gobo-update-signing.pem}
PUBKEY=${PUBKEY:-$REPO/spin/ab/update-signing.pub.pem}
# GoboRefined = the spin's name (unofficial, based on GoboLinux 017.01). The volume label below must
# stay GOBOLINUX_LIVE_INSTALLER: the live boot looks for the medium by it.
OUT=$B/GoboRefined-$VERSION.iso
UPDATE=$B/GoboRefined-$VERSION.update
cd $B
[[ "$VERSION" =~ ^[0-9A-Za-z.-]+$ ]] || { echo "bad VERSION"; exit 1; }
[ -s "$SIGNING_KEY" ] || { echo "no signing key at $SIGNING_KEY (see the header of this script)"; exit 1; }
trap 'rm -f "$SIGNING_KEY"' EXIT

[ -f "$REPO/spin/build-iso.sh" ] && [ -f "$REPO/installer/gobo-install" ] || { echo "REPO=$REPO is not a GoboRefined checkout"; exit 1; }
[ -d "$R/Programs/LiveCD" ] || { echo "$R is not the stock live image tree"; exit 1; }
[ -x "$XORRISO" ] || { echo "no xorriso at $XORRISO"; exit 1; }
[ -s "$PUBKEY" ] || { echo "no public key at $PUBKEY"; exit 1; }

echo "== taking installer, look and spin files from the checkout $REPO"
rm -rf gobo11 ab firmware settings
cp "$REPO/installer/gobo-install" gobo-install
cp "$REPO/spin/welcome.src" welcome.src
cp "$REPO/spin/gobo-command-not-found" gobo-command-not-found
# software-install.txt rides on the ISO for users; fall back if the checkout omitted the md
if [ -f "$REPO/docs/software-install.md" ]
then cp "$REPO/docs/software-install.md" software-install.txt
else printf '%s\n' "See https://github.com/landlubber2/GoboRefined and BUILDING.md." > software-install.txt
fi
cp -r "$REPO/look/gobo11" gobo11
cp -r "$REPO/spin/ab" ab
# 0.8.2: firmware/ (regulatory.db) and settings/ (Settings app)
cp -r "$REPO/spin/firmware" firmware
cp -r "$REPO/spin/settings" settings
bash -n gobo-install
bash -n settings/gobo-app-check && bash -n settings/gobo-devices-scan && sh -n settings/gobo-devices && bash -n settings/gobo-settings-helper && bash -n settings/gobo-report && sh -n settings/gobo-settings && sh -n settings/gobo-askpass && sh -n settings/gobo-bt-agent && sh -n settings/gobo-sound-profile
for f in settings/*.lua settings/pages/*.lua; do luac -p $f; done
sh -n ab/gobo-system-disk && bash -n ab/gobo-update && bash -n ab/gobo-make-system && bash -n ab/gobo-power-button && bash -n ab/dracut/90goboab/module-setup.sh
bash -n ab/gobo-firewall && sh -n gobo11/apply.sh   # 0.9.1
for f in ab/dracut/90goboab/goboab-*.sh; do sh -n $f; done
sh -n ab/mount.ntfs   # 0.10.2
# boot menu template (0.8): numbered first line, no shell-escaped "\$" left in it
head -n 1 ab/grub.cfg.in | grep -q '^# gobo-grub-template [0-9]' && ! grep -qF '\$' ab/grub.cfg.in &&
   grep -qx 'set gobo_layout=btrfs' ab/grub.cfg.in ||
   { echo "ab/grub.cfg.in is not a valid boot menu template"; exit 1; }
openssl pkey -in "$SIGNING_KEY" -pubout 2>/dev/null | cmp -s - "$PUBKEY" ||
   { echo "the signing key does not belong to $PUBKEY"; exit 1; }
grep -q "PRIVATE KEY" "$PUBKEY" && { echo "$PUBKEY holds a private key"; exit 1; }

echo "== adding programs to the live image"
EXTRA="XRandR-Tool Inter JetBrains-Mono Papirus-Icon-Theme Menu-Cache LibFM PCManFM PaVuControl LxRandr LXDM
       Udevil USB-ModeSwitch OnlyOffice CopyQ GoboFiles L3afpad Dnsmasq Linux-Firmware SOF-Firmware SBC
       Intel-Microcode Firefox Btrfs-Progs Rsync"   # 0.8.5: + SBC (Bluetooth audio codec); 0.9.1: + Intel-Microcode, Firefox ESR (replaces the stock 136.0); 0.10: + Btrfs-Progs, Rsync (btrfs layout)
# kernel modules are not linked by SymlinkProgram (/System/Index/lib/modules is a link into Linux)
MODULES="RTL8852AU"
# 0.9.1: the kernel is built by the step "linux" (spin/build-programs.sh); its version is the one
# line of spin/kernel-version (stock image: 6.12.16)
KVER=$(head -n 1 "$REPO/spin/kernel-version")
[[ "$KVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad spin/kernel-version"; exit 1; }
KREL=$KVER-Gobo
for prog in $EXTRA $MODULES
do
   [ -d "$PROGRAMS_FROM/Programs/$prog" ] || { echo "program $prog not built (no $PROGRAMS_FROM/Programs/$prog)"; exit 1; }
   rm -rf $R/Programs/$prog && cp -a "$PROGRAMS_FROM/Programs/$prog" $R/Programs/
done
# 0.8.4: these two replace stock programs of the same name; the build root still has the stock
# version next to the new one (20250309-GIT, 1.4.2): keep only the new version (Current)
# (0.9.1: the same for Firefox: ESR instead of the stock 136.0_bin)
for prog in Linux-Firmware SOF-Firmware Firefox
do
   cur=$(readlink $R/Programs/$prog/Current)
   [ -n "$cur" ] && [ -d "$R/Programs/$prog/$cur" ] || { echo "$prog: no Current version"; exit 1; }
   for d in $R/Programs/$prog/*/
   do
      d=${d%/}
      case "$(basename "$d")" in "$cur"|Settings|Current) ;; *) echo "dropping stock $prog $(basename "$d")"; rm -rf "$d" ;; esac
   done
done
# 0.9.1: the new kernel replaces the stock one: program, Current, the module link in the index
# (/System/Index/lib/modules points at a version, not at Current), kernel and System.map in
# /System/Kernel/Boot (copies of the program's Unmanaged files, as SymlinkProgram makes them).
KSRC="$PROGRAMS_FROM/Programs/Linux/$KVER"
[ "$(cat "$KSRC/Resources/GoboRefinedKernel" 2>/dev/null)" = "$KREL" ] || { echo "kernel $KREL not built (step linux; no $KSRC)"; exit 1; }
OLDKV=$(readlink $R/Programs/Linux/Current)
[[ "$OLDKV" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "unexpected /Programs/Linux/Current: $OLDKV"; exit 1; }
if [ "$OLDKV" != "$KVER" ]
then
   echo "== kernel: $OLDKV -> $KVER"
   rm -rf $R/Programs/Linux/$KVER && cp -a "$KSRC" $R/Programs/Linux/
   rm -rf $R/Programs/Linux/$OLDKV
   ln -sfn $KVER $R/Programs/Linux/Current
   [ -L $R/System/Index/lib/modules ] || { echo "/System/Index/lib/modules is not a link"; exit 1; }
   ln -sfn /Programs/Linux/$KVER/lib/modules $R/System/Index/lib/modules
   if [ -L $R/System/Index/bin/WriteBoot64 ] && [ -e $R/Programs/Linux/$KVER/bin/WriteBoot64 ]
   then ln -sfn /Programs/Linux/$KVER/bin/WriteBoot64 $R/System/Index/bin/WriteBoot64
   fi
   rm -f $R/System/Kernel/Boot/kernel* $R/System/Kernel/Boot/System.map* $R/System/Kernel/Boot/initramfs*
   cp -a $R/Programs/Linux/$KVER/Resources/Unmanaged/System/Kernel/Boot/. $R/System/Kernel/Boot/
fi
[ -f $R/System/Kernel/Boot/kernel-$KREL ] && [ "$(readlink $R/System/Kernel/Boot/kernel)" = "kernel-$KREL" ] ||
   { echo "kernel $KREL is not in /System/Kernel/Boot"; exit 1; }
# 0.8.5: Bluetooth audio. PulseAudio 13.0's Bluetooth modules (build step pulseaudio-bluetooth) go
# next to the stock modules; default.pa (both copies: ProfileInstall installs the Defaults one)
# loads module-bluetooth-policy and module-bluetooth-discover (spin/ab/pulse-bluetooth.pa)
PAMOD=$R/Programs/PulseAudio/13.0/lib/pulse-13.0/modules
[ -d "$PAMOD" ] || { echo "no stock PulseAudio 13.0 modules folder"; exit 1; }
for f in libbluez5-util module-bluez5-discover module-bluez5-device module-bluetooth-discover module-bluetooth-policy
do
   src="$PROGRAMS_FROM/Programs/PulseAudio-Bluetooth/13.0/lib/pulse-13.0/modules/$f.so"
   [ -f "$src" ] || { echo "PulseAudio Bluetooth module $f not built"; exit 1; }
   install -m 755 "$src" $PAMOD/
done
for pa in $R/Programs/PulseAudio/Settings/pulse/default.pa $R/Programs/PulseAudio/13.0/Resources/Defaults/Settings/pulse/default.pa
do
   [ -f $pa ] || { echo "missing $pa"; exit 1; }
   grep -q 'module-bluetooth-discover' $pa && continue
   awk -v ins="$REPO/spin/ab/pulse-bluetooth.pa" '/^### Automatically connect sink and source if JACK server is present/ && !done { while ((getline l < ins) > 0) print l; done = 1 } { print } END { if (!done) exit 1 }' $pa > $pa.new ||
      { echo "default.pa: JACK block not found in $pa"; exit 1; }
   mv $pa.new $pa
   grep -q '^load-module module-bluetooth-discover' $pa || { echo "default.pa not changed: $pa"; exit 1; }
done
# Login screen theme files (title image "GoboRefined", wallpaper, CSS) from spin/lxdm in the
# checkout, so a theme change does not depend on the copy built into /Programs/LXDM.
install -m 644 "$REPO"/spin/lxdm/Gobo11/* $R/Programs/LXDM/0.5.3/share/lxdm/themes/Gobo11/
P=$R/Programs/GoboSpin
rm -rf $P && mkdir -p $P/1.0/bin $P/1.0/share $P/1.0/Resources
install -m 755 gobo-install $P/1.0/bin/gobo-install
install -m 755 gobo-command-not-found $P/1.0/bin/gobo-command-not-found
# 0.8 A/B system: update tool, system tree builder (used by gobo-install and below), the
# initramfs module, the update signing key (public), the cache list, the udev rule that keeps
# the GOBO_* partitions away from devmon/udevil.
install -m 755 ab/gobo-update $P/1.0/bin/gobo-update
install -m 755 ab/gobo-make-system $P/1.0/bin/gobo-make-system
install -m 755 ab/gobo-power-button $P/1.0/bin/gobo-power-button   # 0.8.1 (acpid rule: gobo-make-system)
# 0.8.1: Xorg input hot-plug (X -> gobo-xorg link: gobo-make-system)
install -m 755 ab/gobo-xorg $P/1.0/bin/gobo-xorg
# 0.8.2: "is this device on the system disk?" for the udev rule below and devmon (xinitrc)
install -m 755 ab/gobo-system-disk $P/1.0/bin/gobo-system-disk
mkdir -p $P/1.0/lib
gcc -O2 -Wall -shared -fPIC -o $P/1.0/lib/gobo-udev-dev.so ab/gobo-udev-dev.c -ldl
chmod 755 $P/1.0/lib/gobo-udev-dev.so
mkdir -p $P/1.0/share/gobo-update/dracut $P/1.0/lib/udev/rules.d
cp -r ab/dracut/90goboab $P/1.0/share/gobo-update/dracut/
chmod 755 $P/1.0/share/gobo-update/dracut/90goboab/*.sh
install -m 644 ab/generated-caches ab/grub.cfg.in $P/1.0/share/gobo-update/
# the public key updates for this image must be signed with (the project's, or the builder's own)
install -m 644 "$PUBKEY" $P/1.0/share/gobo-update/update-signing.pub.pem
install -m 644 ab/80-gobo-internal.rules $P/1.0/lib/udev/rules.d/
# 0.8.3: Intel graphics on the modesetting driver, 0.8.4: also xe, amdgpu, radeon (gobo-make-system copies it into
# /System/Settings/X11/xorg.conf.d of every system tree; the live image gets it below)
mkdir -p $P/1.0/share/gobo-xorg
install -m 644 ab/20-gobo-modesetting.conf ab/30-gobo-touchpad.conf $P/1.0/share/gobo-xorg/
mkdir -p $R/System/Settings/X11/xorg.conf.d
install -m 644 ab/20-gobo-modesetting.conf ab/30-gobo-touchpad.conf $R/System/Settings/X11/xorg.conf.d/
# 0.8.2: Wi-Fi regulatory database (wireless-regdb, ISC; spin/firmware/wireless-regdb/SOURCE):
# cfg80211 loads regulatory.db(.p7s) from /lib/firmware (= /System/Index/lib/firmware)
mkdir -p $P/1.0/lib/firmware
install -m 644 firmware/wireless-regdb/regulatory.db firmware/wireless-regdb/regulatory.db.p7s $P/1.0/lib/firmware/
# 0.8.2: Settings app (Lua + lgi + GTK 3), its root helper, askpass, system report
install -m 755 settings/gobo-settings settings/gobo-settings-helper settings/gobo-askpass settings/gobo-report settings/gobo-bt-agent settings/gobo-sound-profile settings/gobo-devices settings/gobo-devices-scan settings/gobo-app-check settings/gobo-pin-to-start $P/1.0/bin/   # 0.9.6: + gobo-pin-to-start
mkdir -p $P/1.0/share/gobo-settings/pages $P/1.0/share/applications
install -m 644 settings/main.lua settings/common.lua settings/bt-agent.lua settings/pactl.lua settings/sound-profile.lua $P/1.0/share/gobo-settings/   # 0.8.4: + Bluetooth pairing agent, 0.8.5: + sound card watcher
install -m 644 settings/pages/*.lua $P/1.0/share/gobo-settings/pages/
install -m 644 settings/gobo-settings.desktop $P/1.0/share/applications/
# 0.9.2: Device Manager (detection library, what the project knows about some hardware, lookup URLs)
install -m 644 settings/devices.lua settings/known-drivers.tsv settings/device-lookup.conf $P/1.0/share/gobo-settings/
install -m 644 settings/gobo-devices.desktop $P/1.0/share/applications/
# 0.9.1: the default programs of a Simple account; the firewall (rules in one readable file) and
# the kernel security settings (both loaded by BootUp lines from gobo-make-system)
install -m 644 settings/simple-apps.default $P/1.0/share/gobo-settings/
install -m 755 ab/gobo-firewall $P/1.0/bin/gobo-firewall
mkdir -p $P/1.0/share/gobo-firewall $P/1.0/share/gobo-security
install -m 644 ab/firewall.rules $P/1.0/share/gobo-firewall/firewall.rules
install -m 644 ab/gobo-sysctl.conf $P/1.0/share/gobo-security/sysctl.conf
mkdir -p $P/1.0/share/doc
install -m 644 firmware/wireless-regdb/LICENSE $P/1.0/share/doc/wireless-regdb-LICENSE
install -m 644 software-install.txt $P/1.0/share/doc/software-install.txt
# 0.9.5: the offline GoboRefined manual (Settings > Manual) and the look's New > Word document template
mkdir -p $P/1.0/share/doc/goborefined-manual
install -m 644 "$REPO/spin/manual/index.html" $P/1.0/share/doc/goborefined-manual/index.html
[ -s "gobo11/templates/New document.docx" ] || { echo "missing look template New document.docx"; exit 1; }
cp -r gobo11 $P/1.0/share/gobo11
echo "GoboRefined (unofficial spin of GoboLinux 017.01): thin installer and desktop look." > $P/1.0/Resources/Description
echo "$VERSION" > $P/1.0/share/spin-version
ln -sfn 1.0 $P/Current
# never a private key in the image
grep -rqs -e "PRIVATE KEY" $P && { echo "a private key ended up in GoboSpin"; exit 1; }
mount -t proc proc $R/proc
# 0.9.7: the C library 2.38 (build step glibc) becomes the system's; the stock 2.30 stays in
# /Programs/Glibc/2.30 with nothing linked to it. The index is switched from THIS machine, not
# inside the chroot: until the loader and libc.so.6 links point at one version, nothing may run in
# the image. After that every chroot command below (SymlinkProgram, ldconfig, depmod, dracut,
# gobo-make-system's ProfileInstall) runs on 2.38.
GV=2.38 GOLDV=2.30
GSRC="$PROGRAMS_FROM/Programs/Glibc/$GV"
[ -x "$GSRC/lib/ld-linux-x86-64.so.2" ] && [ -f "$GSRC/lib/libc.so.6" ] && [ -f "$GSRC/lib/libcrypt.so.1" ] &&
   [ -s "$GSRC/lib/locale/locale-archive" ] || { echo "Glibc $GV not built (step glibc; no $GSRC)"; exit 1; }
[ "$(readlink $R/Programs/Glibc/Current)" = "$GOLDV" ] && [ -d $R/Programs/Glibc/$GOLDV/lib ] || { echo "the image's C library is not the stock $GOLDV"; exit 1; }
echo "== C library: Glibc $GOLDV -> $GV"
rm -rf $R/Programs/Glibc/$GV && cp -a "$GSRC" $R/Programs/Glibc/
# libraries 2.30 had and 2.38 has not (e.g. libSegFault.so): nothing in the image may need them
for f in $R/Programs/Glibc/$GOLDV/lib/*.so.*
do
   b=$(basename "$f")
   case "$b" in *-$GOLDV.so|*-1.0.so) continue ;; esac   # the versioned file names behind the links
   [ -e "$R/Programs/Glibc/$GV/lib/$b" ] || echo "$b"
done > $B/glibc-gone
if [ -s $B/glibc-gone ]
then
   echo "sonames of $GOLDV not in $GV: $(tr '\n' ' ' < $B/glibc-gone)"
   find $R/Programs -path "$R/Programs/Glibc" -prune -o -type f \( -perm -u+x -o -name '*.so*' \) -print0 |
      xargs -0 -r readelf -d 2> /dev/null | awk '/^File: / { f = $2 } /\(NEEDED\)/ { gsub(/[\[\]]/, "", $5); print $5 "\t" f }' |
      grep -F -f <(sed 's/.*/&\t/' $B/glibc-gone) > $B/glibc-gone-users || true
   [ ! -s $B/glibc-gone-users ] || { echo "programs need libraries that $GV does not have:"; head -n 20 $B/glibc-gone-users; exit 1; }
fi
# every index link into 2.30 goes (listed first, then deleted: an overlay walk), then 2.38's lib/ and
# bin/ are linked by hand: loader, libc.so.6 & co. switch in one go
find $R/System -xdev -lname "/Programs/Glibc/$GOLDV/*" -print0 > $B/glibc-old-links
echo "index links into Glibc $GOLDV: $(tr -cd '\0' < $B/glibc-old-links | wc -c)"
xargs -0 -r rm -f < $B/glibc-old-links
for sub in lib bin
do
   for f in $R/Programs/Glibc/$GV/$sub/*
   do
      b=$(basename "$f") dst=$R/System/Index/$sub/$(basename "$f")
      if [ ! -L "$dst" ] && [ ! -e "$dst" ]
      then ln -s "/Programs/Glibc/$GV/$sub/$b" "$dst"
      else echo "kept (another program's, or a real folder): $sub/$b -> $(readlink "$dst")"
      fi
   done
done
ln -sfn $GV $R/Programs/Glibc/Current
[ "$(chroot $R readlink -f /lib64/ld-linux-x86-64.so.2)" = "/Programs/Glibc/$GV/lib/ld-linux-x86-64.so.2" ] &&
   [ "$(chroot $R readlink -f /System/Index/lib/libc.so.6)" = "/Programs/Glibc/$GV/lib/libc.so.6" ] ||
   { echo "loader or libc.so.6 do not point at Glibc $GV"; exit 1; }
chroot $R /bin/true || { echo "the image does not run programs on Glibc $GV"; exit 1; }
chroot $R SymlinkProgram Glibc $GV | tail -n 1
chroot $R ldconfig
left=$(find $R/System -xdev -lname "/Programs/Glibc/$GOLDV/*" | head -n 5)
[ -z "$left" ] || { echo "links into Glibc $GOLDV left: $left"; exit 1; }
chroot $R ldd --version | head -n 1 | grep -q " $GV\$" || { chroot $R ldd --version | head -n 1; echo "ldd is not $GV"; exit 1; }
chroot $R getconf GNU_LIBC_VERSION | grep -qx "glibc $GV" || { echo "getconf does not report glibc $GV"; exit 1; }
[ "$(chroot $R readlink -f /System/Index/include/stdio.h)" = "/Programs/Glibc/$GV/include/stdio.h" ] || { echo "headers are not $GV's"; exit 1; }
# logins: libcrypt 2.38 makes the same SHA-512 hash as openssl (as the installer writes them)
h_new=$(chroot $R python3 -c 'import crypt; print(crypt.crypt("Gobo test 1", "$6$gobosalt1234567"))')
h_ref=$(chroot $R openssl passwd -6 -salt gobosalt1234567 'Gobo test 1')
[ -n "$h_ref" ] && [ "$h_new" = "$h_ref" ] || { echo "libcrypt in the image gives another hash"; exit 1; }
chroot $R locale -a | grep -qx pl_PL.utf8 && chroot $R locale -a | grep -qx en_US.utf8 || { echo "locales missing"; exit 1; }
chroot $R env LC_ALL=pl_PL.UTF-8 date -d 2026-11-18 +%A | grep -qx 'środa' || { echo "Polish locale does not work"; exit 1; }
echo "Glibc $GV: $(chroot $R ldd --version | head -n 1); $(chroot $R locale -a | wc -l) locales"
# 0.8.4: Linux-Firmware 20261019 and SOF-Firmware 2026.09.2 replaced the stock versions above
# (20250309-GIT, 1.4.2); drop the index links that still point at the old versions so
# SymlinkProgram links the new trees (and no dangling link is left behind)
# (list first, then delete: deleting while find walks an overlay makes it report vanished entries)
find $R/System/Index/lib/firmware \( -lname '/Programs/SOF-Firmware/*' -o -lname '/Programs/Linux-Firmware/*' \) -print0 > $B/old-firmware-links
xargs -0 -r rm -f < $B/old-firmware-links
find $R/System/Index/lib/firmware -mindepth 1 -depth -type d -empty -print0 | xargs -0 -r rmdir 2>/dev/null || true
# 0.9.1: the index links of the stock Firefox (bin/firefox, menu entry, icon) go before the new
# version is linked, as for the firmware above
for d in bin share/applications share/icons
do find $R/System/Index/$d -maxdepth 1 -lname '/Programs/Firefox/*' -print0
done > $B/old-firefox-links
xargs -0 -r rm -f < $B/old-firefox-links
for prog in $EXTRA
do chroot $R SymlinkProgram $prog | tail -n 1
done
# 0.9.1: Firefox ESR is the browser; Intel microcode where dracut looks for it; nothing in the
# index or the boot folder still points at the old kernel
[ "$(chroot $R readlink -f /System/Index/bin/firefox)" = "/Programs/Firefox/$(readlink $R/Programs/Firefox/Current)/bin/firefox" ] ||
   { echo "firefox is not linked to the new version"; exit 1; }
chroot $R test -e /System/Index/share/applications/firefox.desktop || { echo "firefox.desktop not linked"; exit 1; }
[ -n "$(chroot $R sh -c 'ls /lib/firmware/intel-ucode/ 2>/dev/null | head -n 1')" ] || { echo "Intel microcode not linked into /lib/firmware"; exit 1; }
stale=$(find $R/System/Index $R/System/Kernel/Boot -maxdepth 3 -lname "*Programs/Linux/*" ! -lname "*Programs/Linux/$KVER/*" ! -lname "*Programs/Linux/Current/*" | head -n 5)
[ -z "$stale" ] || { echo "links to another kernel version: $stale"; exit 1; }
# 0.9.1: current certificate authorities (build step ca-bundle) over the image's bundle files:
# CAcerts' ca-bundle.crt (2016; both copies because of ProfileInstall) and the bundle curl and
# git read (/System/Settings/ssl/certs/ca-certificates.crt, 2024). The single-certificate
# folder next to it (OpenSSL's CApath, 2024) stays as it is.
CAB="$PROGRAMS_FROM/Programs/CA-Bundle/Current/share/ca-bundle/ca-bundle.crt"
[ -s "$CAB" ] || { echo "CA bundle not built (step ca-bundle)"; exit 1; }
for f in $R/Programs/CAcerts/Settings/ssl/ca-bundle.crt $R/Programs/CAcerts/Current/Resources/Defaults/Settings/ssl/ca-bundle.crt \
         $R/System/Settings/ssl/certs/ca-certificates.crt
do
   if [ -f $f ] && [ ! -L $f ]
   then install -m 644 "$CAB" $f; echo "certificate bundle refreshed: ${f#$R}"
   else echo "certificate bundle NOT refreshed (no plain file): ${f#$R}"
   fi
done
# 0.9.8: one session bus address. DBus 1.12's own session.conf (share/dbus-1) includes the "legacy" file
# /System/Settings/dbus-1/session.conf, which in 017.01 is a full copy of it with its own <listen>: the
# session bus listened twice and DBUS_SESSION_BUS_ADDRESS held two addresses ("a;b"). Valid D-Bus, but
# the Dart dbus package (Flutter apps such as AppImage Pool) refuses it ("duplicate key 'guid'") and the
# app stays a white window. The legacy file becomes an empty configuration (both copies: ProfileInstall).
for f in $R/Programs/DBus/Settings/dbus-1/session.conf $R/Programs/DBus/Current/Resources/Defaults/Settings/dbus-1/session.conf
do
   [ -f $f ] && [ ! -L $f ] || { echo "no plain D-Bus session.conf: ${f#$R}"; exit 1; }
   cat > $f <<'DBUSCONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<!-- GoboRefined: empty on purpose. The session bus configuration is DBus's own share/dbus-1/session.conf,
     which includes this file; a copy of it here made the session bus listen on two addresses. -->
<busconfig>
</busconfig>
DBUSCONF
done
n=$(chroot $R sh -c 'grep -c "<listen>" /usr/share/dbus-1/session.conf /System/Settings/dbus-1/session.conf' | awk -F: '{ s += $2 } END { print s }')
[ "$n" = 1 ] || { echo "the session bus would listen on $n addresses"; exit 1; }
chroot $R SymlinkProgram GoboSpin | tail -n 1
chroot $R test -e /System/Index/lib/firmware/regulatory.db.p7s || { echo "regulatory.db not linked into lib/firmware"; exit 1; }
# 0.8.2: the hotspot (Settings > Hotspot) needs dnsmasq; Bluetooth uses the stock BlueZ 5.54
chroot $R sh -c "command -v dnsmasq" > /dev/null || { echo "dnsmasq not linked"; exit 1; }
chroot $R test -e /System/Index/bin/bluetoothctl || { echo "bluetoothctl missing"; exit 1; }
# 0.8.5: Bluetooth audio pieces reachable where PulseAudio looks
chroot $R test -e /usr/lib/pulse-13.0/modules/module-bluez5-device.so || { echo "PulseAudio Bluetooth modules not reachable"; exit 1; }
chroot $R sh -c "ldd /usr/lib/pulse-13.0/modules/module-bluez5-device.so /usr/lib/pulse-13.0/modules/libbluez5-util.so | grep -q 'not found'" &&
   { echo "PulseAudio Bluetooth modules: a library is missing"; exit 1; }
# 0.8.4: Intel SOF firmware reachable where the kernel looks (/lib/firmware/intel/...)
for f in sof/sof-tgl.ri sof-tplg/sof-hda-generic-2ch.tplg sof-ipc4/tgl/sof-tgl.ri sof-ipc4-tplg sof-ace-tplg
do chroot $R test -e /lib/firmware/intel/$f || { echo "SOF firmware: /lib/firmware/intel/$f missing"; exit 1; }
done
# 0.8.4: the new firmware collection is linked (Intel AX210 Wi-Fi/Bluetooth as samples), and no
# link in lib/firmware points at a program version that is gone
for f in iwlwifi-ty-a0-gf-a0-89.ucode.zst intel/ibt-0041-0041.sfi.zst
do chroot $R test -e /lib/firmware/$f || { echo "linux-firmware: /lib/firmware/$f missing"; exit 1; }
done
dangling=$(chroot $R find /System/Index/lib/firmware -xtype l | head -n 5)
[ -z "$dangling" ] || { echo "dangling firmware links: $dangling"; exit 1; }
echo "== Wi-Fi driver (RTL8852AU) into the kernel's updates directory, module index"
for prog in $MODULES
do
   for ko in $R/Programs/$prog/Current/lib/modules/$KREL/updates/*.ko
   do
      mkdir -p $R/Programs/Linux/Current/lib/modules/$KREL/updates
      ln -sfn /Programs/$prog/Current/lib/modules/$KREL/updates/$(basename $ko) \
         $R/Programs/Linux/Current/lib/modules/$KREL/updates/$(basename $ko)
   done
done
chroot $R depmod -a $KREL
chroot $R modinfo -k $KREL -F alias 8852au | grep -qi 'v2357p013F' || { echo "8852au not in the module index"; exit 1; }
echo "== command-not-found hint: name commands that work (sudo Compile), not InstallPackage"
sed -i 's/^\(\s*\)CommandNotFound \$command$/\1gobo-command-not-found $command/' \
   $R/Programs/Scripts/Current/Functions/CommandNotFound
for f in $R/Programs/Scripts/Settings/bashrc $R/Programs/Scripts/Current/Resources/Defaults/Settings/bashrc
do sed -i 's/^\(\s*\)CommandNotFound \$1 ||/\1gobo-command-not-found $1 ||/' $f
done
grep -q gobo-command-not-found $R/Programs/Scripts/Current/Functions/CommandNotFound
grep -q gobo-command-not-found $R/Programs/Scripts/Settings/bashrc
echo "== refreshing the font cache and the icon caches"
chroot $R fc-cache -f > /dev/null
for t in Papirus Papirus-Dark Papirus-Light hicolor
do chroot $R gtk-update-icon-cache -q -f /System/Index/share/icons/$t
done
echo "== refreshing the MIME database (LibFM adds its types)"
chroot $R update-mime-database /System/Index/share/mime
# GoboNet's backend must be setuid root (its upstream "make install" does chmod 4755);
# the 017.01 package lost the bit, so Wi-Fi from the taskbar fails for normal users.
chmod 4755 $R/Programs/GoboNet/Current/bin/gobonet_backend
# udevil mounts USB drives for normal users: setuid root (cp -a keeps it; make sure)
chmod 4755 $R/Programs/Udevil/Current/bin/udevil
# 0.10.2: its NTFS helper (mount(8) runs /sbin/mount.ntfs for "-t ntfs"): ntfs3, read-only when
# Windows is hibernated or the volume is dirty (spin/ab/mount.ntfs; also used by boot-disks)
install -m 755 ab/mount.ntfs $R/Programs/Udevil/Current/sbin/mount.ntfs
# 0.6: the desktop session may run the Wi-Fi adapter switch (gobo-wifi-switch, in USB-ModeSwitch)
# as root, with exactly this argument and nothing else. The live user is root; installed users
# are in group "users". The installer's ProfileInstall replaces every program's Settings with
# Current/Resources/Defaults/Settings, so the rule goes into both copies (0.6 ISO test: with only
# Settings/sudoers, installed systems had no rule).
for SUDOERS in $R/Programs/Sudo/Settings/sudoers $R/Programs/Sudo/Current/Resources/Defaults/Settings/sudoers
do
   grep -q gobo-wifi-switch $SUDOERS || \
      echo '%users ALL=(root) NOPASSWD: /System/Index/bin/gobo-wifi-switch --session' >> $SUDOERS
   chroot $R visudo -c -f ${SUDOERS#$R} > /dev/null
done
[ -x $R/Programs/USB-ModeSwitch/Current/bin/gobo-wifi-switch ] || { echo "gobo-wifi-switch missing"; exit 1; }
grep -q 'gobo-wifi-switch --udev' $R/Programs/USB-ModeSwitch/Current/lib/udev/rules.d/40-gobo-realtek-wifi.rules
# 0.6 file tools: Trash window + purge, folder colours (PCManFM menu entry = libfm custom action)
for f in bin/gobo-trash bin/gobo-trash-purge bin/gobo-folder-colour share/file-manager/actions/gobo-folder-colour.desktop
do [ -e $R/Programs/GoboFiles/Current/$f ] || { echo "GoboFiles: $f missing"; exit 1; }
done
# (inside the chroot: GoboLinux links are absolute and would resolve against the build machine)
chroot $R test -e /System/Index/share/file-manager/actions/gobo-folder-colour.desktop || { echo "folder colour action not linked"; exit 1; }
# no stray link inside /Mount/Media (USB drives are mounted there; see gobo-install)
[ -L $R/Mount/Media/Media ] && rm -f $R/Mount/Media/Media
# 0.10: eudev's 64-btrfs.rules runs '${exec_prefix}/bin/udevadm' (a configure variable left unexpanded in
# 017.01): "failed to execute" for every btrfs device event, and with a btrfs disk the boot's udev start
# took about 11 s longer. Fixed in the image (dracut copies the rule into the initramfs below).
BTRULE=$(ls $R/Programs/Eudev/*/lib/udev/rules.d/64-btrfs.rules 2>/dev/null | head -n 1)
[ -f "$BTRULE" ] || { echo "no eudev 64-btrfs.rules in the image"; exit 1; }
sed -i 's|\${exec_prefix}/bin/udevadm|/System/Index/bin/udevadm|' "$BTRULE"
grep -q 'exec_prefix' "$BTRULE" && { echo "64-btrfs.rules not fixed"; exit 1; }
grep -q 'RUN+="/System/Index/bin/udevadm trigger' "$BTRULE" || { echo "64-btrfs.rules: unexpected content"; exit 1; }
chroot $R test -x /System/Index/bin/mkfs.btrfs && chroot $R test -x /System/Index/bin/btrfs && chroot $R test -x /System/Index/bin/rsync ||
   { echo "btrfs-progs or rsync not linked in the image"; exit 1; }
echo "== initramfs with the A/B root (dracut module goboab; same modules as the stock image + goboab)"
DRACUT_MODS=$R/Programs/Dracut/Current/lib/dracut/modules.d
ln -sfn /Programs/GoboSpin/Current/share/gobo-update/dracut/90goboab $DRACUT_MODS/90goboab
mount --rbind /sys $R/System/Kernel/Objects && mount --make-rslave $R/System/Kernel/Objects
# 0.9.7: dracut 103's dracut-install climbs from each /sys/devices/platform node with realpath() until the
# result is "/sys/devices". Through GoboLinux's /sys link it is "/System/Kernel/Objects/devices", so the
# loop only ends when realpath() fails on the ever longer path: glibc 2.30's did, 2.38's does not (it
# hung for 80 minutes). So during this dracut run /sys is a real folder with sysfs on it; the link
# comes back right after.
[ "$(readlink $R/sys)" = System/Kernel/Objects ] || { echo "unexpected /sys in the image"; exit 1; }
rm $R/sys && mkdir $R/sys && mount --rbind /sys $R/sys && mount --make-rslave $R/sys
mount --rbind /dev $R/System/Kernel/Devices && mount --make-rslave $R/System/Kernel/Devices
IMG=/Programs/Linux/Current/Resources/Unmanaged/System/Kernel/Boot/initramfs-$KREL.img
chroot $R dracut --kver $KREL --force --no-hostonly --early-microcode -L 4 --add goboab $IMG > $B/dracut.log 2>&1 ||
   { tail -n 20 $B/dracut.log; exit 1; }
umount -R $R/System/Kernel/Devices; umount -R $R/System/Kernel/Objects
umount -R $R/sys && rmdir $R/sys && ln -s System/Kernel/Objects $R/sys
[ "$(readlink $R/sys)" = System/Kernel/Objects ] || { echo "/sys link not restored"; exit 1; }
cp $R$IMG $R/System/Kernel/Boot/initramfs-$KREL.img
chroot $R lsinitrd $IMG > $B/lsinitrd.log
grep -q 'bin/goboab-root' $B/lsinitrd.log && grep -q 'overlay.ko' $B/lsinitrd.log ||
   { echo "goboab missing from the initramfs"; exit 1; }
# 0.10: the btrfs layout - btrfs module, goboab's btrfs path, the fixed udev rule
grep -q '/btrfs.ko' $B/lsinitrd.log || { echo "btrfs module missing from the initramfs"; exit 1; }
GR=$(grep -o '[^ ]*bin/goboab-root$' $B/lsinitrd.log | head -n 1)
chroot $R lsinitrd -f "$GR" $IMG | grep -q 'subvol=@system-' || { echo "the initramfs's goboab-root ($GR) has no btrfs path"; exit 1; }
if grep -q '64-btrfs.rules' $B/lsinitrd.log
then
   chroot $R lsinitrd -f "${BTRULE#$R/}" $IMG | grep -q exec_prefix && { echo "the initramfs has the unfixed 64-btrfs.rules"; exit 1; }
fi
# 0.9.1: processor microcode for both makers at the front of the initramfs, modules of the new kernel
grep -q 'kernel/x86/microcode/GenuineIntel.bin' $B/lsinitrd.log && grep -q 'kernel/x86/microcode/AuthenticAMD.bin' $B/lsinitrd.log ||
   { echo "early microcode missing from the initramfs"; exit 1; }
grep -q "lib/modules/$KREL/" $B/lsinitrd.log || { echo "the initramfs has no modules of $KREL"; exit 1; }

echo "== live medium: kernel $KREL with the stock live initramfs, its modules replaced"
# The ISO starts /isolinux/kernel with /isolinux/initramfs (the BIOS and UEFI menus name these two
# files); the live image now holds only the modules of the new kernel, so both are replaced. The
# stock live initramfs (dracut, dmsquash-live) is kept as it is, except: the modules it carries
# are taken from the new kernel (the same list, plus what they newly depend on), and the
# microcode part in front is the one made above (Intel + AMD).
LIVE=$B/live-initramfs
SKIPCPIO=$R/Programs/Dracut/Current/lib/dracut/skipcpio
[ -x $SKIPCPIO ] || { echo "no skipcpio in the image's dracut"; exit 1; }
rm -rf $LIVE && mkdir -p $LIVE/root
"$XORRISO" -osirrox on -indev "stdio:$ISO" -extract /isolinux/initramfs $LIVE/initramfs.stock > $B/xorriso-extract.log 2>&1 ||
   { tail -n 20 $B/xorriso-extract.log; exit 1; }
chmod 600 $LIVE/initramfs.stock
$SKIPCPIO $LIVE/initramfs.stock | zstd -dc | (cd $LIVE/root && cpio -id --quiet) || { echo "could not unpack the stock live initramfs"; exit 1; }
OLDM=$(ls -d $LIVE/root/Programs/Linux/*/lib/modules/*)
[ -d "$OLDM/kernel" ] || { echo "stock live initramfs: no kernel modules where expected ($OLDM)"; exit 1; }
LIVEOLD=$(basename "${OLDM%/lib/modules/*}")
NEWM=$LIVE/root/Programs/Linux/$KVER/lib/modules/$KREL
SRCM=$R/Programs/Linux/$KVER/lib/modules/$KREL
if [ "$LIVEOLD" != "$KVER" ]
then
   (cd "$OLDM" && find kernel -type f -name '*.ko*') > $LIVE/modules.stock
   awk -v list=$LIVE/modules.stock '
      BEGIN { while ((getline l < list) > 0) want[l] = 1 }
      { m = $1; sub(/:$/, "", m); dep[m] = $0 }
      END {
         do {
            added = 0
            for (m in dep) if (m in want) { n = split(dep[m], a, " "); for (i = 2; i <= n; i++) if (!(a[i] in want)) { want[a[i]] = 1; added = 1 } }
         } while (added)
         for (m in want) print m
      }' $SRCM/modules.dep | LC_ALL=C sort > $LIVE/modules.new
   mkdir -p $NEWM
   gone=0
   while IFS= read -r m
   do
      if [ -f "$SRCM/$m" ]
      then install -D -m 644 "$SRCM/$m" "$NEWM/$m"
      else echo "live initramfs: $m is not in kernel $KREL"; gone=$((gone + 1))
      fi
   done < $LIVE/modules.new
   [ "$gone" -le 15 ] || { echo "live initramfs: $gone modules of the stock list are missing in $KREL"; exit 1; }
   install -m 644 $SRCM/modules.builtin $SRCM/modules.builtin.modinfo $SRCM/modules.order $NEWM/
   rm -rf "$LIVE/root/Programs/Linux/$LIVEOLD"
   depmod -b $LIVE/root/Programs/Linux/$KVER $KREL
   find $LIVE/root -lname "*Programs/Linux/$LIVEOLD/*" > $LIVE/links
   [ -s $LIVE/links ] || { echo "live initramfs: no module link to retarget"; exit 1; }
   while IFS= read -r l
   do t=$(readlink "$l"); ln -sfn "${t/Programs\/Linux\/$LIVEOLD\//Programs/Linux/$KVER/}" "$l"
   done < $LIVE/links
   [ -f $LIVE/root/System/Index/lib/modules/$KREL/modules.dep ] || { echo "live initramfs: the modules of $KREL are not reachable"; exit 1; }
fi
total=$(stat -c %s $R$IMG); rest=$($SKIPCPIO $R$IMG | wc -c)
[ "$rest" -gt 0 ] && [ "$rest" -lt "$total" ] || { echo "the new initramfs has no early microcode part"; exit 1; }
head -c $((total - rest)) $R$IMG > $LIVE/initramfs
(cd $LIVE/root && find . -mindepth 1 -print0 | LC_ALL=C sort -z | cpio -o -0 -H newc --quiet | zstd -q -15 -T0) >> $LIVE/initramfs
cp $LIVE/initramfs $R/gobo-live-initramfs.tmp
chroot $R lsinitrd /gobo-live-initramfs.tmp > $B/lsinitrd-live.log || true
rm -f $R/gobo-live-initramfs.tmp
grep -q "lib/modules/$KREL/kernel/.*squashfs" $B/lsinitrd-live.log && grep -q 'dmsquash-live' $B/lsinitrd-live.log ||
   { echo "the live initramfs is not complete"; exit 1; }
cp $R/System/Kernel/Boot/kernel-$KREL $LIVE/kernel
rm -rf $LIVE/root
ls -l $LIVE
umount $R/proc

echo "== look for the live user and for new users (both are copied from the skeleton)"
for skel in $R/Programs/EnhancedSkel/017.01/Resources/Defaults/Settings/skel $R/Programs/EnhancedSkel/Settings/skel
do [ -d $skel ] && sh gobo11/apply.sh $skel system
done

echo "== welcome text"
printf "$(cat welcome.src)\n" > $R/Programs/LiveCD/017.01/Data/Language/Welcome_en_US

echo "== packing the live image"
# nothing may stay mounted inside the image tree (a stopped earlier run can leave proc behind)
grep -q " $R/" /proc/mounts && { echo "still mounted inside $R:"; grep " $R/" /proc/mounts; exit 1; }
rm -f $B/gobolinux-live.squashfs $OUT
mksquashfs $R $B/gobolinux-live.squashfs -comp zstd -b 131072 -noappend -no-progress > $B/mksquashfs.log

echo "== system update file: the pristine system tree, made the way gobo-install makes slot A"
rm -rf $B/system $UPDATE $B/update.manifest $B/update.trailer
mkdir $B/system
bash $R/Programs/GoboSpin/1.0/bin/gobo-make-system --log $B/make-system.log $B/gobolinux-live.squashfs $B/system
INSTALLED=$(du -sb $B/system | cut -f1)
mksquashfs $B/system $UPDATE -comp zstd -b 131072 -noappend -no-progress -xattrs > $B/mksquashfs-update.log
rm -rf $B/system
IMAGE_SIZE=$(stat -c %s $UPDATE)
{
   echo "GOBOREFINED-UPDATE 2"   # 0.10: format 2 (btrfs layout); 0.9.x gobo-update accepts only 1 and refuses this file
   echo "name=GoboRefined"
   echo "layout=btrfs"
   echo "version=$VERSION"
   echo "image_size=$IMAGE_SIZE"
   echo "image_sha256=$(sha256sum $UPDATE | cut -d' ' -f1)"
   echo "installed_bytes=$INSTALLED"
   echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > $B/update.manifest
openssl dgst -sha256 -sign "$SIGNING_KEY" -out $B/update.sig $B/update.manifest
rm -f "$SIGNING_KEY"
openssl dgst -sha256 -verify $R/Programs/GoboSpin/1.0/share/gobo-update/update-signing.pub.pem \
   -signature $B/update.sig $B/update.manifest
{
   cat $B/update.manifest
   echo "-----BEGIN SIGNATURE-----"
   openssl base64 -A < $B/update.sig; echo
   echo "-----END SIGNATURE-----"
} > $B/update.trailer
[ "$(stat -c %s $B/update.trailer)" -le 8192 ] || { echo "update trailer too long"; exit 1; }
truncate -s 8192 $B/update.trailer
cat $B/update.trailer >> $UPDATE
rm -f $B/update.sig $B/update.trailer
ls -la $UPDATE
sha256sum $UPDATE

echo "== writing the ISO (boot records are replayed from the stock ISO)"
"$XORRISO" -indev "stdio:$ISO" -outdev $OUT \
   -boot_image any replay \
   -rm /gobolinux-live.squashfs /isolinux/kernel /isolinux/initramfs -- \
   -map $B/gobolinux-live.squashfs /gobolinux-live.squashfs \
   -map $LIVE/kernel /isolinux/kernel \
   -map $LIVE/initramfs /isolinux/initramfs \
   -volid GOBOLINUX_LIVE_INSTALLER > $B/xorriso.log 2>&1 || { tail -n 20 $B/xorriso.log; exit 1; }

ls -la $OUT
sha256sum $OUT
echo BUILD-DONE
