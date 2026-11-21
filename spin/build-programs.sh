#!/bin/bash
# Build the programs GoboRefined adds to the stock GoboLinux 017.01 image, one step at a time,
# GoboLinux style: each one goes to /Programs/<Name>/<Version> (settings in
# /Programs/<Name>/Settings) and is activated with SymlinkProgram. Run as root on a 017.01
# system. build/build.sh runs every step, in order, inside its own build root (a chroot of the
# stock image), so nothing here touches the computer the build runs on.
#
#   bash build-programs.sh <step>
#
# Steps, in this order (later ones need earlier ones):
#   xorriso xrandr inter jetbrains-mono papirus menu-cache libfm pcmanfm pavucontrol lxrandr
#   lxdm udevil usb-modeswitch rtl8852au onlyoffice copyq gobofiles l3afpad dnsmasq linux-firmware
#   sof-firmware
# (menu-cache builds LibFM "extra only" first, so libfm and pcmanfm must follow it.)
#
# Environment:
#   SRC   folder holding the downloaded sources (file names as in build/sources.manifest;
#         build/build.sh downloads and checks them). Default /Data/Build/src3.
#   WORK  scratch folder for unpacked sources. Default /Data/Build/work3.
#   SPIN  the repository's spin/ folder (patches, LXDM theme, gobo-wifi-switch, gobofiles).
#         Default: the folder this script is in.
set -e
SRC=${SRC:-/Data/Build/src3}
WORK=${WORK:-/Data/Build/work3}
SPIN=${SPIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
[ -d "$SPIN/patches" ] || { echo "SPIN=$SPIN is not the repository's spin/ folder"; exit 1; }
mkdir -p $WORK

# need <file>...: the sources must be there (build/build.sh fetches them)
need() {
   local f
   for f in "$@"
   do [ -f "$SRC/$f" ] || { echo "missing source $SRC/$f (run build/build.sh fetch)"; exit 1; }
   done
}
# gcc 14 turns several old warnings into errors; these 2016-era sources need them as warnings again
CF="-O2 -fcommon -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion"

# gobo_configure <Name> <Version> [extra configure options...]
gobo_configure() {
   local name=$1 ver=$2; shift 2
   ./configure --prefix=/Programs/$name/$ver \
      --sysconfdir=/Programs/$name/Settings \
      --localstatedir=/Data/Variable \
      --mandir=/Programs/$name/$ver/share/man \
      --disable-static "$@"
}

# unpack <tarball> [<folder it unpacks to>]: fresh source tree, cd into it
unpack() {
   local t=$1 d=${2:-}
   need $t
   [ -n "$d" ] || d=$(basename $t | sed -E 's/\.tar\.(xz|gz|bz2)$//')
   rm -rf $WORK/$d
   tar xf $SRC/$t -C $WORK
   cd $WORK/$d
}

# resources <Name> <Version> <Summary> <Licence> <Homepage>: Resources for data-only programs
resources() {
   local P=/Programs/$1/$2
   mkdir -p $P/Resources
   echo x86_64 > $P/Resources/Architecture
   : > $P/Resources/Dependencies
   printf '[Name] %s\n[Summary] %s\n[License] %s\n[Homepage] %s\n' "$1" "$3" "$4" "$5" > $P/Resources/Description
   ln -sfn $2 /Programs/$1/Current
}

# finish <Name> <Version> <Description>: make install, Resources, Current link, SymlinkProgram
finish() {
   local name=$1 ver=$2
   make -j2
   make install
   [ "$(type -t post_install)" = function ] && post_install
   ln -sfn $ver /Programs/$name/Current
   mkdir -p /Programs/$name/$ver/Resources
   echo "$3" > /Programs/$name/$ver/Resources/Description
   if [ -d /Programs/$name/Settings ]
   then
      mkdir -p /Programs/$name/$ver/Resources/Defaults
      rm -rf /Programs/$name/$ver/Resources/Defaults/Settings
      cp -a /Programs/$name/Settings /Programs/$name/$ver/Resources/Defaults/Settings
   fi
   SymlinkProgram $name $ver | tail -n 1
}

case "$1" in
xorriso)
   # GNU xorriso, only a build tool (writes the ISO; 017.01 has no ISO authoring tool).
   # Not part of the image: installed to /Data/Build/xorriso-inst.
   unpack xorriso-1.5.6.pl02.tar.gz xorriso-1.5.6
   ./configure --prefix=/Data/Build/xorriso-inst
   make -j2
   make install
   /Data/Build/xorriso-inst/bin/xorriso -version | head -n 1
   ;;
xrandr)
   # the xrandr command (017.01 ships only the XRandR library); needed by displays.sh and LxRandr
   unpack xrandr-1.5.2.tar.xz
   ./configure --prefix=/Programs/XRandR-Tool/1.5.2
   finish XRandR-Tool 1.5.2 "xrandr command-line tool (X.Org), built from source."
   ;;
inter)
   # Inter 4.1, the static TTFs of the text family (Light to Bold, with italics)
   need Inter-4.1.zip
   P=/Programs/Inter/4.1 D=$WORK/inter
   rm -rf $D $P && mkdir -p $D $P/share/fonts/Inter $P/doc
   unzip -q $SRC/Inter-4.1.zip -d $D
   for w in Light Regular Medium SemiBold Bold
   do
      [ $w = Regular ] && it=Italic || it=${w}Italic
      install -m 644 $D/extras/ttf/Inter-$w.ttf $D/extras/ttf/Inter-$it.ttf $P/share/fonts/Inter/
   done
   install -m 644 $D/LICENSE.txt $P/doc/LICENSE
   resources Inter 4.1 "Inter UI typeface (static TTF, text family)" "SIL Open Font License 1.1" "https://rsms.me/inter/"
   SymlinkProgram Inter 4.1 | tail -n 1
   ;;
jetbrains-mono)
   need JetBrainsMono-2.304.zip
   P=/Programs/JetBrains-Mono/2.304 D=$WORK/jbmono
   rm -rf $D $P && mkdir -p $D $P/share/fonts/JetBrainsMono $P/doc
   unzip -q $SRC/JetBrainsMono-2.304.zip -d $D
   for s in Regular Italic Medium MediumItalic Bold BoldItalic
   do install -m 644 $D/fonts/ttf/JetBrainsMono-$s.ttf $P/share/fonts/JetBrainsMono/
   done
   install -m 644 $D/OFL.txt $P/doc/LICENSE
   resources JetBrains-Mono 2.304 "JetBrains Mono monospace typeface" "SIL Open Font License 1.1" "https://www.jetbrains.com/lp/mono/"
   SymlinkProgram JetBrains-Mono 2.304 | tail -n 1
   ;;
papirus)
   # Papirus, Papirus-Dark, Papirus-Light: only the sizes 16-64 (no 8, 18, 42, 84, 96, 128,
   # no @2x HiDPI folders); index.theme lists only the folders that are kept.
   unpack papirus-icon-theme-20260801.tar.gz
   P=/Programs/Papirus-Icon-Theme/20260801
   rm -rf $P && mkdir -p $P/share/icons $P/doc
   for t in Papirus Papirus-Dark Papirus-Light
   do
      mkdir -p $P/share/icons/$t
      for s in 16x16 22x22 24x24 32x32 48x48 64x64
      do if [ -d $t/$s ]; then cp -a $t/$s $P/share/icons/$t/; fi
      done
      awk -F= '
         /^Directories=/ {
            n = split($2, a, ","); s = ""
            for (i = 1; i <= n; i++) { split(a[i], b, "/"); if (b[1] ~ /^(16|22|24|32|48|64)x/) s = s (s == "" ? "" : ",") a[i] }
            print "Directories=" s; next }
         /^ScaledDirectories=/ { print "ScaledDirectories="; next }
         { print }' $t/index.theme > $P/share/icons/$t/index.theme
   done
   install -m 644 AUTHORS LICENSE $P/doc/
   resources Papirus-Icon-Theme 20260801 "Papirus icon theme (sizes 16-64 only, no HiDPI @2x)" "GPL-3.0" "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme"
   SymlinkProgram Papirus-Icon-Theme 20260801 | tail -n 1
   for t in Papirus Papirus-Dark Papirus-Light
   do gtk-update-icon-cache -q -f $P/share/icons/$t || true
   done
   ;;
menu-cache)
   # menu-cache needs libfm-extra (part of libfm, built "extra only" first; the libfm step replaces it)
   unpack libfm-1.2.5.tar.xz
   gobo_configure LibFM 1.2.5 --with-extra-only
   finish LibFM 1.2.5 "File management library used by PCManFM (GTK 3 build)."
   unpack menu-cache-1.0.2.tar.xz
   gobo_configure Menu-Cache 1.0.2 --libexecdir=/Programs/Menu-Cache/1.0.2/lib CFLAGS="$CF"
   finish Menu-Cache 1.0.2 "Freedesktop.org menu cache library and daemon (LXDE)."
   ;;
libfm)
   unpack libfm-1.2.5.tar.xz
   # 0.6 (spin/patches/libfm-1.2.5-gobo.patch, served by vm/serve.js): fixed "USB drives"
   # side-pane entry + one entry per mounted stick; folder icons from <folder>/.directory
   # (folder colours); only files on the home file system go to the trash (others: asked,
   # then deleted for good). Custom actions are on again (0.6, folder colours): the tarball
   # ships the C files generated from Vala, so no Vala compiler is needed.
   patch -p1 < $SPIN/patches/libfm-1.2.5-gobo.patch
   gobo_configure LibFM 1.2.5 --with-gtk=3 --disable-exif CFLAGS="$CF"
   grep -q '^#define HAVE_ACTIONS 1' config.h
   finish LibFM 1.2.5 "File management library used by PCManFM (GTK 3 build)."
   # the shortcut editor is not useful as a menu entry (after "make install": the lab build
   # once wrote this before it, which only worked because the file was there from a build before)
   grep -q '^NoDisplay=true' /Programs/LibFM/1.2.5/share/applications/lxshortcut.desktop ||
      echo "NoDisplay=true" >> /Programs/LibFM/1.2.5/share/applications/lxshortcut.desktop
   ;;
pcmanfm)
   unpack pcmanfm-1.2.5.tar.xz
   # 0.6 (spin/patches/pcmanfm-1.2.5-gobo.patch): simple search on Ctrl+F and a toolbar
   # button ("this folder only" / "this folder and all folders inside it"); the old dialog
   # stays as Tools -> Advanced Search (Ctrl+Shift+F). Desktop mode (0.6, desktop icons): a right
   # click on an empty spot runs $GOBO_DESKTOP_MENU_COMMAND (Awesome's menu; Ctrl+right click =
   # PCManFM's own), and the icon area follows _NET_WORKAREA read directly (set by the look)
   patch -p1 < $SPIN/patches/pcmanfm-1.2.5-gobo.patch
   gobo_configure PCManFM 1.2.5 --with-gtk=3 CFLAGS="$CF"
   finish PCManFM 1.2.5 "Lightweight file manager (GTK 3 build)."
   # Awesome owns the wallpaper: hide the "Desktop Preferences" entry (it manages desktop icons)
   echo "NoDisplay=true" >> /Programs/PCManFM/1.2.5/share/applications/pcmanfm-desktop-pref.desktop
   ;;
pavucontrol)
   unpack pavucontrol-4.0.tar.xz
   gobo_configure PaVuControl 4.0 --disable-lynx CXXFLAGS="-O2 -std=c++11"
   finish PaVuControl 4.0 "PulseAudio volume control window."
   ;;
lxrandr)
   unpack lxrandr-0.3.1.tar.xz
   gobo_configure LxRandr 0.3.1 --enable-gtk3 CFLAGS="$CF"
   finish LxRandr 0.3.1 "Monitor configuration tool (LXDE, GTK 3 build)."
   # "video-display" is not found by the Awesome menu in Papirus-Dark; use the settings icon
   sed -i "s/^Icon=.*/Icon=preferences-desktop-display/" /Programs/LxRandr/0.3.1/share/applications/lxrandr.desktop
   ;;
lxdm)
   # LXDM installs its settings straight into /etc/lxdm and /etc/pam.d; move them into
   # /Programs/LXDM/Settings (SymlinkProgram links them back) and replace them with the
   # spin's files from spin/lxdm.
   post_install() {
      local S=/Programs/LXDM/Settings
      mkdir -p $S/lxdm $S/pam.d
      mv /etc/lxdm/* $S/lxdm/ && rmdir /etc/lxdm
      rm -f /etc/pam.d/lxdm
      local F=$SPIN/lxdm
      install -m 640 $F/lxdm.conf $S/lxdm/lxdm.conf
      install -m 755 $F/Xsession $S/lxdm/Xsession
      install -m 755 $F/PostLogout $S/lxdm/PostLogout
      install -m 644 $F/pam.d-lxdm $S/pam.d/lxdm
      local T=/Programs/LXDM/0.5.3/share/lxdm/themes
      rm -rf $T/Gobo11 && cp -a $T/Industrial $T/Gobo11
      rm -f $T/Gobo11/wave.svg $T/Gobo11/gtkrc $T/Gobo11/greeter.ui
      install -m 644 $F/Gobo11/* $T/Gobo11/
   }
   unpack lxdm-0.5.3.tar.xz
   gobo_configure LXDM 0.5.3 --enable-gtk3 --with-pam --disable-consolekit \
      --libexecdir=/Programs/LXDM/0.5.3/lib CFLAGS="$CF"
   finish LXDM 0.5.3 "Lightweight X11 display manager (GTK 3 build, PAM, no ConsoleKit)."
   ;;
udevil)
   # USB sticks without udisks/gvfs/polkit (0.5): udevil is a small setuid mount helper,
   # devmon (shell script, same package) the automounter started from ~/.xinitrc.
   post_install() {
      local C=/Programs/Udevil/Settings/udevil/udevil.conf
      # Mount under /Mount/Media/<label> (GoboLinux's place for removable media; /media links there).
      # GoboLinux's /dev is /System/Kernel/Devices, which udevil sees after resolving links.
      # The kernel's exfat and ntfs3 drivers do not take the FUSE-only options of the stock file.
      sed -i \
         -e 's|^allowed_media_dirs = .*|allowed_media_dirs = /Mount/Media, /media, /run/media/$USER|' \
         -e 's|^allowed_devices = .*|allowed_devices = /dev/*, /System/Kernel/Devices/*|' \
         -e 's|^default_options_exfat .*|default_options_exfat     = nosuid, noexec, nodev, noatime, fmask=0133, dmask=0022, uid=$UID, gid=$GID, iocharset=utf8|' \
         -e 's|^default_options_ntfs .*|default_options_ntfs      = nosuid, noexec, nodev, noatime, fmask=0133, dmask=0022, uid=$UID, gid=$GID, iocharset=utf8|' \
         $C
      chown root:root $C && chmod 644 $C
      chmod 4755 /Programs/Udevil/0.4.4/bin/udevil
      # The 6.12 kernel has only the ntfs3 driver; its legacy "ntfs" type mounts read-only.
      # mount(8) runs /sbin/mount.<type> helpers, so "ntfs" is sent to ntfs3 (read-write).
      mkdir -p /Programs/Udevil/0.4.4/sbin
      printf '%s\n' '#!/bin/sh' \
         '# udevil/devmon mount NTFS as "ntfs"; use the read-write ntfs3 kernel driver instead.' \
         'exec /bin/mount -i -t ntfs3 "$@"' > /Programs/Udevil/0.4.4/sbin/mount.ntfs
      chmod 755 /Programs/Udevil/0.4.4/sbin/mount.ntfs
   }
   unpack udevil-0.4.4.tar.gz
   # libudev ignores "udev" event monitors on GoboLinux (/dev is a link, not a devtmpfs mount),
   # so devmon never heard of new drives: listen to kernel events and wait for udevd instead.
   # (spin/patches/udevil-0.4.4-gobo-monitor.patch)
   patch -p1 < $SPIN/patches/udevil-0.4.4-gobo-monitor.patch
   gobo_configure Udevil 0.4.4 --disable-systemd CFLAGS="$CF"
   finish Udevil 0.4.4 "Mounts removable drives as a normal user (setuid helper) and devmon automounter."
   ;;
usb-modeswitch)
   # Realtek Wi-Fi USB adapters (TP-Link Archer TX20U Plus, ...) first appear as a "driver CD"
   # with ID 0bda:1a2b and must be switched to Wi-Fi mode. Only the usb_modeswitch binary is
   # installed (no Tcl dispatcher, no data package): our own udev rule calls it for 0bda:1a2b.
   V=2.6.1 P=/Programs/USB-ModeSwitch/2.6.1
   unpack usb-modeswitch-2.6.1.tar.bz2
   make usb_modeswitch CFLAGS="-O2"
   rm -rf $P && mkdir -p $P/bin $P/share/man/man1 $P/lib/udev/rules.d $P/Resources
   install -m 755 usb_modeswitch $P/bin/
   install -m 644 usb_modeswitch.1 $P/share/man/man1/
   # 0.6: the rule starts gobo-wifi-switch (spin/gobo-wifi-switch): it
   # leaves udev at once, waits, retries the switch and logs to /var/log/gobo-wifi-switch.log.
   # (0.5 ran usb_modeswitch straight from the rule; on the real PC nothing happened, while the
   # same command typed later worked.) The desktop session runs it too (sudo rule: build-iso.sh).
   bash -n $SPIN/gobo-wifi-switch
   install -m 755 $SPIN/gobo-wifi-switch $P/bin/gobo-wifi-switch
   cat > $P/lib/udev/rules.d/40-gobo-realtek-wifi.rules <<'RULES'
# GoboRefined: Realtek Wi-Fi USB adapters (e.g. TP-Link Archer TX20U Plus) first show up
# as a virtual "driver CD" with ID 0bda:1a2b. Switch them (gobo-wifi-switch ejects the CD in
# the background, with retries), so the adapter re-appears with its Wi-Fi ID (e.g. 2357:013f,
# handled by the 8852au driver), and keep devmon from mounting the CD.
# Two triggers: the USB device itself, and its CD drive once usb-storage has set it up
# (gobo-wifi-switch runs one copy at a time; the second finds nothing left to do).
# Rules are read from /usr/lib/udev/rules.d (= /System/Index/lib/udev/rules.d), where
# SymlinkProgram links this file; "add" also matches the coldplug at boot (Eudev's Udev task).
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="0bda", ATTR{idProduct}=="1a2b", RUN+="/System/Index/bin/gobo-wifi-switch --udev"
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sr*", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="1a2b", RUN+="/System/Index/bin/gobo-wifi-switch --udev"
SUBSYSTEM=="block", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="1a2b", ENV{UDISKS_PRESENTATION_NOPOLICY}="1", ENV{UDISKS_IGNORE}="1"
RULES
   echo "Switches USB devices out of their 'driver CD' mode (binary only, spin udev rule + gobo-wifi-switch for Realtek Wi-Fi)." > $P/Resources/Description
   ln -sfn $V /Programs/USB-ModeSwitch/Current
   SymlinkProgram USB-ModeSwitch $V | tail -n 1
   ;;
rtl8852au)
   # Out-of-tree driver for RTL8852AU/RTL8832AU USB Wi-Fi (TP-Link Archer TX20U Plus 2357:013f/0141);
   # the 6.12 kernel's rtw89 has no USB support. Built against the image's own kernel tree.
   # The kernel tree lacks include/config/kernel.release, so KERNELRELEASE is passed by hand,
   # and the driver's Makefile is used through kbuild directly (it needs TopDIR for that).
   # Source: GitHub's archive of commit 865ab0f (same files as a git checkout of that commit).
   # 0.9.1: against the kernel of the step "linux" (version in spin/kernel-version), which stays
   # next to the build root's own stock kernel (/Programs/Linux/Current is not changed here).
   KVER=$(head -n 1 $SPIN/kernel-version); KREL=$KVER-Gobo
   REV=865ab0f V=20240506 P=/Programs/RTL8852AU/20240506
   KM=/Programs/Linux/$KVER/lib/modules/$KREL
   [ -f $KM/build/Module.symvers ] || { echo "kernel $KREL is not built (step linux)"; exit 1; }
   FULL=865ab0fa91471d595c283d2f3db323f7f15455f5
   unpack rtl8852au-$FULL.tar.gz rtl8852au-$FULL
   # Newer 6.12.y kernels carry the 6.13 change that gives cfg80211's set_monitor_channel a
   # "struct net_device *dev" argument; the driver (2024) does not know it. Add the (unused)
   # argument when this kernel's header has it.
   if grep -A1 '(\*set_monitor_channel)' $KM/build/include/net/cfg80211.h | grep -q 'struct net_device \*dev'; then
      sed -i 's/^static int cfg80211_rtw_set_monitor_channel(struct wiphy \*wiphy$/&, struct net_device *dev/' os_dep/linux/ioctl_cfg80211.c
      grep -q '^static int cfg80211_rtw_set_monitor_channel(struct wiphy \*wiphy, struct net_device \*dev$' os_dep/linux/ioctl_cfg80211.c \
         || { echo "could not adapt set_monitor_channel to this kernel"; exit 1; }
   fi
   make -j2 LD=ld.bfd -C $KM/build M=$PWD KERNELRELEASE=$KREL TopDIR=$PWD CONFIG_RTL8852AU=m modules
   [ "$(modinfo -F vermagic ./8852au.ko | cut -d' ' -f1)" = "$KREL" ] || { echo "8852au.ko is not for $KREL"; exit 1; }
   rm -rf $P && mkdir -p $P/lib/modules/$KREL/updates $P/Resources $P/doc
   install -m 644 8852au.ko $P/lib/modules/$KREL/updates/
   cp README.md $P/doc/
   echo "Realtek RTL8852AU/RTL8832AU USB Wi-Fi driver (lwfinger/rtl8852au $REV) for kernel $KREL." > $P/Resources/Description
   ln -sfn $V /Programs/RTL8852AU/Current
   # /System/Index/lib/modules is a link into the Linux program, so SymlinkProgram cannot
   # merge modules: link the .ko into the kernel's "updates" directory instead.
   mkdir -p $KM/updates
   ln -sfn /Programs/RTL8852AU/Current/lib/modules/$KREL/updates/8852au.ko $KM/updates/8852au.ko
   depmod -b /Programs/Linux/$KVER $KREL
   ;;
linux)
   # 0.9.1: the newest kernel of the 6.12 long-term series (the stock image has 6.12.16 from
   # February 2025), built with the stock kernel's own configuration; "make olddefconfig" gives
   # options that are new since 6.12.16 their default. Laid out like the stock Linux program:
   # lib/modules/<release>, kernel and System.map under Resources/Unmanaged/System/Kernel/Boot,
   # and a "build" tree with what compiling a driver against this kernel needs (headers, scripts,
   # Module.symvers: not the whole source as the stock program has, which was 756 MB).
   # The version is the one line of spin/kernel-version. /Programs/Linux/Current of the build
   # root stays the stock kernel; spin/build-iso.sh switches the image over.
   # The compile takes 1-2 hours on 2 processors. The tree is unpacked outside the scratch folder
   # (/Data/Build/linux-<version>) so that a stopped or repeated run goes on where it was; it is
   # removed at the end unless the file /Data/Build/keep-linux-tree exists.
   # 0.9.3: apply upstream GoboHide (Recipes Linux/6.12.16/01-gobohide.patch). Without it the
   # FHS compatibility links (/bin, /etc, /usr, ...) show again — the point of GoboLinux.
   KVER=$(head -n 1 $SPIN/kernel-version); KREL=$KVER-Gobo
   OLDV=6.12.16 OLD=/Programs/Linux/6.12.16 P=/Programs/Linux/$KVER
   [[ "$KVER" =~ ^6\.12\.[0-9]+$ ]] || { echo "spin/kernel-version: '$KVER' is not a 6.12.y version"; exit 1; }
   [ "$KVER" != "$OLDV" ] || { echo "spin/kernel-version is the stock kernel"; exit 1; }
   need linux-$KVER.tar.xz
   T=/Data/Build/linux-$KVER
   if [ ! -f $T/.gobo-unpacked ]
   then
      rm -rf $T
      tar xf $SRC/linux-$KVER.tar.xz -C /Data/Build
      : > $T/.gobo-unpacked
   fi
   cd $T
   if [ ! -f .gobo-gobohide-applied ]
   then
      patch -p1 < $SPIN/patches/linux-6.12.16-gobohide.patch > /Data/Build/linux-gobohide-patch.log 2>&1 || {
         echo "GoboHide patch failed on linux-$KVER (see /Data/Build/linux-gobohide-patch.log)";
         tail -n 40 /Data/Build/linux-gobohide-patch.log; exit 1; }
      # reused tree from a build without GoboHide: drop old objects so namei/readdir rebuild
      if [ -f .config ]
      then make LD=ld.bfd clean > /Data/Build/linux-clean-after-gobohide.log 2>&1 || true
      fi
      : > .gobo-gobohide-applied
   fi
   [ -f .config ] || cp $OLD/lib/modules/$OLDV-Gobo/build/.config .config
   # (the image's "ld" is the gold linker, which cannot link a kernel: GNU ld by name)
   make LD=ld.bfd olddefconfig > /Data/Build/linux-olddefconfig.log 2>&1 || { tail -n 20 /Data/Build/linux-olddefconfig.log; exit 1; }
   # GoboHide defaults to y in the patch; force it if olddefconfig left it unset
   if ! grep -q '^CONFIG_GOBOHIDE_FS=y$' .config
   then
      sed -i '/CONFIG_GOBOHIDE_FS/d' .config
      echo 'CONFIG_GOBOHIDE_FS=y' >> .config
      make LD=ld.bfd olddefconfig > /Data/Build/linux-olddefconfig-gobohide.log 2>&1 || {
         tail -n 20 /Data/Build/linux-olddefconfig-gobohide.log; exit 1; }
   fi
   grep -q '^CONFIG_GOBOHIDE_FS=y$' .config || { echo "CONFIG_GOBOHIDE_FS=y missing after olddefconfig"; exit 1; }
   [ "$(make -s LD=ld.bfd kernelrelease)" = "$KREL" ] || { echo "the kernel calls itself $(make -s LD=ld.bfd kernelrelease), expected $KREL"; exit 1; }
   echo "compiling Linux $KREL with $(nproc) jobs (log: /Data/Build/linux-make.log in the build root)"
   make LD=ld.bfd -j$(nproc) bzImage modules > /Data/Build/linux-make.log 2>&1 || { grep -B 5 -A 5 -m 3 'Error ' /Data/Build/linux-make.log; tail -n 30 /Data/Build/linux-make.log; exit 1; }
   rm -rf $P && mkdir -p $P/Resources/Unmanaged/System/Kernel/Boot $P/doc/linux-$KVER
   make -s LD=ld.bfd INSTALL_MOD_PATH=$P modules_install > /Data/Build/linux-modules-install.log 2>&1 || { tail -n 30 /Data/Build/linux-modules-install.log; exit 1; }
   KM=$P/lib/modules/$KREL
   [ -f $KM/modules.dep ] && [ -d $KM/kernel ] || { echo "modules_install left no modules in $KM"; exit 1; }
   UB=$P/Resources/Unmanaged/System/Kernel/Boot
   install -m 644 arch/x86/boot/bzImage $UB/kernel-$KREL
   install -m 644 System.map $UB/System.map-$KREL
   ln -s kernel-$KREL $UB/kernel
   ln -s System.map-$KREL $UB/System.map
   # the "build" tree: what compiling an out-of-tree module needs
   rm -rf $KM/build $KM/source && mkdir -p $KM/build
   b=$KM/build
   install -m 644 .config Makefile Module.symvers System.map $b/
   install -D -m 644 kernel/Makefile $b/kernel/Makefile
   install -D -m 644 arch/x86/Makefile $b/arch/x86/Makefile
   cp -a scripts $b/
   install -D -m 755 tools/objtool/objtool $b/tools/objtool/objtool
   cp -a include $b/
   cp -a arch/x86/include $b/arch/x86/
   install -D -m 644 arch/x86/kernel/asm-offsets.s $b/arch/x86/kernel/asm-offsets.s
   find . -name 'Kconfig*' -not -path './Documentation/*' | while IFS= read -r f; do install -D -m 644 "$f" "$b/$f"; done
   find $b -type f \( -name '*.o' -o -name '.*.cmd' -o -name '*.a' \) -delete
   find -L $b -type l -delete 2>/dev/null || true
   # never the key the modules were signed with (made for this build only)
   rm -f $b/certs/signing_key.pem $b/certs/signing_key.x509
   ln -s build $KM/source
   chown -R root:root $P
   # Resources: as the stock program, with this version's source
   for f in Architecture Dependencies BuildDependencies Description UseFlags UnmanagedFiles
   do if [ -f $OLD/Resources/$f ]; then cp $OLD/Resources/$f $P/Resources/$f; fi
   done
   echo "[File] https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz" > $P/Resources/PackageSource
   if [ -d $OLD/bin ]; then cp -a $OLD/bin $P/bin; fi
   install -m 644 COPYING README $P/doc/linux-$KVER/
   # a marker for spin/build-iso.sh: this tree is complete
   echo "$KREL" > $P/Resources/GoboRefinedKernel
   du -sh $P $KM/kernel $KM/build
   cd /
   if [ ! -e /Data/Build/keep-linux-tree ]; then rm -rf $T; fi
   ;;
intel-microcode)
   # 0.9.1: Intel's processor microcode updates (security and stability fixes the processor
   # loads at every start). dracut puts them, with AMD's from linux-firmware, at the front of
   # the initramfs ("early microcode"). Data only; Intel's licence allows redistribution.
   V=20261110 P=/Programs/Intel-Microcode/20261110
   D=Intel-Linux-Processor-Microcode-Data-Files-microcode-$V
   unpack intel-microcode-$V.tar.gz $D
   rm -rf $P && mkdir -p $P/lib/firmware/intel-ucode $P/share/doc/intel-microcode
   install -m 644 intel-ucode/* $P/lib/firmware/intel-ucode/
   install -m 644 license releasenote.md $P/share/doc/intel-microcode/
   [ "$(ls $P/lib/firmware/intel-ucode | wc -l)" -ge 50 ] || { echo "intel-ucode: too few files"; exit 1; }
   chown -R root:root $P
   resources Intel-Microcode $V "Intel processor microcode updates (loaded early at every start)" \
      "Intel microcode licence (redistributable; share/doc/intel-microcode/license)" "https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files"
   du -sh $P
   ;;
firefox)
   # 0.9.1: the current Firefox ESR (extended support release: security fixes without feature
   # changes), Mozilla's official Linux x86_64 build, laid out like the stock Firefox 136.0
   # program (package/ = the tarball, bin/firefox = the stock launcher, menu entry and icon).
   # Its own updater is switched off (programs are read-only here; a new version comes with a
   # system update). Profiles made by the stock 136.0 open in it (it is newer).
   V=153.7.0esr P=/Programs/Firefox/153.7.0esr OLD=/Programs/Firefox/136.0_bin
   need firefox-$V.tar.xz
   [ -x $OLD/bin/firefox ] && [ -f $OLD/share/applications/firefox.desktop ] || { echo "the stock Firefox program looks different"; exit 1; }
   rm -rf $P && mkdir -p $P/bin $P/Resources $P/share/applications $P/share/icons
   tar xf $SRC/firefox-$V.tar.xz -C $P
   mv $P/firefox $P/package
   [ -x $P/package/firefox ] && [ -f $P/package/libxul.so ] || { echo "unexpected Firefox tarball layout"; exit 1; }
   chown -R root:root $P
   chmod -R go-w $P
   mkdir -p $P/package/distribution
   printf '%s\n' '{' '  "policies": {' '    "DisableAppUpdate": true' '  }' '}' > $P/package/distribution/policies.json
   # Launcher. Left alone, the ESR build starts an empty profile of its own ("default-esr") next
   # to the one the stock Firefox 136 used, and the bookmarks seem gone. So: one fixed profile,
   # ~/.mozilla/firefox/goborefined-esr, made at the first start as a copy of the person's old
   # default profile (bookmarks, passwords, history, add-ons). The old profile is not touched:
   # after a rollback the old Firefox opens it as before (it refuses profiles of a newer version).
   cat > $P/bin/firefox <<'LAUNCHER'
#!/bin/bash
# GoboRefined launcher for Firefox ESR (see spin/build-programs.sh, step firefox).
pkgdir=$(readlink -f $(dirname $(which firefox))/../package)
for a in "$@"
do case "$a" in
      -P|--P|-profile|--profile|-ProfileManager|--ProfileManager|-v|--version|-h|--help) exec "$pkgdir/firefox" "$@" ;;
   esac
done
[ -n "$HOME" ] || exec "$pkgdir/firefox" "$@"
base="$HOME/.mozilla/firefox"
prof="$base/goborefined-esr"
if [ ! -d "$prof" ]
then
   mkdir -p "$base"
   old=
   if [ -f "$base/profiles.ini" ]
   then
      # the profile marked Default=1 (the stock image's skeleton has one: gobolinux017.01.default)
      rel=$(awk -F= '/^\[/ { if (d && p != "") { print p; exit } p = ""; d = 0 }
                     $1 == "Path" { p = $2 } $1 == "Default" && $2 == "1" { d = 1 }
                     END { if (d && p != "") print p }' "$base/profiles.ini" | head -n 1)
      case "$rel" in
         "") ;;
         /*) old="$rel" ;;
         *)  old="$base/$rel" ;;
      esac
   fi
   [ -n "$old" ] && [ -f "$old/places.sqlite" ] || old=
   tmp="$prof.new.$$"
   rm -rf "$tmp"
   if [ -n "$old" ] && cp -a "$old" "$tmp" 2>/dev/null
   then rm -f "$tmp/lock" "$tmp/.parentlock"
   else rm -rf "$tmp"; mkdir -p "$tmp"
   fi
   chmod 700 "$tmp"
   mv "$tmp" "$prof" 2>/dev/null || rm -rf "$tmp"
fi
[ -d "$prof" ] || exec "$pkgdir/firefox" "$@"
exec "$pkgdir/firefox" --profile "$prof" "$@"
LAUNCHER
   chmod 755 $P/bin/firefox
   bash -n $P/bin/firefox
   install -m 644 $OLD/share/applications/firefox.desktop $P/share/applications/firefox.desktop
   # the ESR build names its windows "firefox-esr"
   sed -i 's/^StartupWMClass=.*/StartupWMClass=firefox-esr/' $P/share/applications/firefox.desktop
   install -m 644 $P/package/browser/chrome/icons/default/default128.png $P/share/icons/firefox.png
   for f in Architecture Dependencies Description UseFlags Wrappers
   do if [ -f $OLD/Resources/$f ]; then cp $OLD/Resources/$f $P/Resources/$f; fi
   done
   echo "[File] https://ftp.mozilla.org/pub/firefox/releases/$V/linux-x86_64/en-US/firefox-$V.tar.xz" > $P/Resources/PackageSource
   ln -sfn $V /Programs/Firefox/Current
   $P/package/firefox --version
   ;;
ca-bundle)
   # 0.9.1: current certificate authorities (Mozilla's list as published by the curl project).
   # Only a carrier: spin/build-iso.sh copies the file over the image's old bundle files.
   V=2026-11-05 P=/Programs/CA-Bundle/2026-11-05
   need cacert-$V.pem
   rm -rf $P && mkdir -p $P/share/ca-bundle
   install -m 644 $SRC/cacert-$V.pem $P/share/ca-bundle/ca-bundle.crt
   [ "$(grep -c 'BEGIN CERTIFICATE' $P/share/ca-bundle/ca-bundle.crt)" -ge 100 ] || { echo "ca-bundle: too few certificates"; exit 1; }
   resources CA-Bundle $V "Certificate authorities trusted for TLS (Mozilla's list, from curl.se)" "MPL-2.0" "https://curl.se/docs/caextract.html"
   ;;
onlyoffice)
   # ONLYOFFICE Desktop Editors (AGPL-3.0), the official x64 binary tarball (needs only glibc 2.17;
   # the image has 2.30). Downloaded from the ONLYOFFICE GitHub releases into $SRC.
   V=10.0.0 P=/Programs/OnlyOffice/10.0.0
   T=onlyoffice-desktopeditors-x64-$V.tar.xz
   need $T
   rm -rf $WORK/onlyoffice && mkdir -p $WORK/onlyoffice && tar xJf $SRC/$T -C $WORK/onlyoffice
   cd $WORK/onlyoffice
   rm -rf $P && mkdir -p $P/bin $P/lib $P/share $P/Resources
   cp -a opt/onlyoffice/desktopeditors $P/lib/desktopeditors
   cp -a usr/share/icons usr/share/doc usr/share/licenses $P/share/
   # launcher: their script, pointed at /Programs/OnlyOffice/Current instead of /opt, and using
   # the window manager's title bar (under Awesome its own title bar's restore button does nothing)
   sed -e 's|/opt/onlyoffice/desktopeditors|/Programs/OnlyOffice/Current/lib/desktopeditors|g' \
       -e 's|^exec $APP_PATH/DesktopEditors "$@"|exec $APP_PATH/DesktopEditors --system-title-bar "$@"|' \
      usr/bin/onlyoffice-desktopeditors > $P/bin/onlyoffice-desktopeditors
   grep -q -e '--system-title-bar "\$@"' $P/bin/onlyoffice-desktopeditors
   chmod 755 $P/bin/onlyoffice-desktopeditors
   # menu entry (Office category). Plain text, Markdown and PDF stay with the editors/viewers
   # that already open them; OnlyOffice is offered for office formats.
   mkdir -p $P/share/applications
   sed -e 's|/usr/bin/onlyoffice-desktopeditors|onlyoffice-desktopeditors|g' \
       -e '/^MimeType=/s#text/plain;##; /^MimeType=/s#text/markdown;##; /^MimeType=/s#application/pdf;##' \
       usr/share/applications/onlyoffice-desktopeditors.desktop > $P/share/applications/onlyoffice-desktopeditors.desktop
   echo "ONLYOFFICE Desktop Editors: documents, spreadsheets, presentations (official binary build)." > $P/Resources/Description
   ln -sfn $V /Programs/OnlyOffice/Current
   SymlinkProgram OnlyOffice $V | tail -n 1
   gtk-update-icon-cache -q -f /System/Index/share/icons/hicolor || true
   update-desktop-database -q /System/Index/share/applications 2>/dev/null || true
   ;;
copyq)
   # 0.6: clipboard history (Win+Shift+V shows it in the look's own popup, spin/cliphist.lua).
   # CopyQ 6.4.0 is the last release series that builds with Qt 5.14 and cmake 3.16 (7.x wants
   # Qt 5.15+). No KDE Frameworks on the image: Qt's own notifications instead of KNotifications.
   # Source: https://github.com/hluk/CopyQ/archive/refs/tags/v6.4.0.tar.gz -> $SRC/CopyQ-6.4.0.tar.gz
   V=6.4.0 P=/Programs/CopyQ/6.4.0
   need CopyQ-$V.tar.gz
   rm -rf $WORK/CopyQ-$V && tar xzf $SRC/CopyQ-$V.tar.gz -C $WORK
   # X11 only: its Wayland clipboard needs extra-cmake-modules, Wayland and QtWaylandClient,
   # none of which the image has. Drop that part (it is used only when not running on X11).
   cd $WORK/CopyQ-$V/src/platform/x11
   sed -i '/^# Wayland clipboard/,/^list(APPEND copyq_LIBRARIES systemclipboard)/d' x11platform.cmake
   sed -i -e '/#include "systemclipboard\/waylandclipboard.h"/d' \
      -e 's|m_selectionSupported = WaylandClipboard::instance()->isSelectionSupported();|m_selectionSupported = false;|' \
      -e '/connect(WaylandClipboard::instance(), &WaylandClipboard::changed,/,+1d' \
      -e 's|WaylandClipboard::instance()->setMimeData(data, qmode);|delete data;|' \
      -e 's|return WaylandClipboard::instance()->mimeData( modeToQClipboardMode(mode) );|return DummyClipboard::mimeData(mode);|' \
      x11platformclipboard.cpp
   ! grep -q -e WaylandClipboard -e systemclipboard x11platformclipboard.cpp x11platform.cmake
   mkdir -p $WORK/CopyQ-$V/build && cd $WORK/CopyQ-$V/build
   # Qt 5.14 was built for prefix /usr; its cmake files then want /usr/mkspecs, /usr/plugins...,
   # which the image does not have (/usr holds only links). Temporary links for the build only.
   # (/usr/plugins already exists, holding webkit/: link Qt's plugin directories one by one)
   tmp_links=
   trap 'rm -f $tmp_links' EXIT
   for d in mkspecs qml $(cd /Programs/Qt/Current && ls -d plugins/*)
   do [ -e /usr/$d ] || { ln -s /Programs/Qt/Current/$d /usr/$d; tmp_links="$tmp_links /usr/$d"; }
   done
   cmake .. -DCMAKE_INSTALL_PREFIX=$P -DCMAKE_BUILD_TYPE=Release -DWITH_TESTS=OFF \
      -DWITH_NATIVE_NOTIFICATIONS=OFF -DPLUGIN_INSTALL_PREFIX=$P/lib/copyq/plugins
   make -j2
   rm -rf $P && make install
   mkdir -p $P/Resources
   echo "CopyQ clipboard manager: keeps the last copied texts and pictures (used by the desktop's Win+Shift+V)." > $P/Resources/Description
   # no autostart entry from the program itself (~/.xinitrc starts it), menu entry kept
   rm -rf $P/etc
   ln -sfn $V /Programs/CopyQ/Current
   SymlinkProgram CopyQ $V | tail -n 1
   ;;
gobofiles)
   # 0.6: the spin's own file tools (sources in spin/gobofiles/):
   # gobo-trash (Trash window, GTK 3, C), gobo-trash-purge (all deleting from the Trash, age
   # limit), gobo-folder-colour + the PCManFM menu entry "Folder colour..." (libfm custom action).
   V=0.6 P=/Programs/GoboFiles/0.6
   rm -rf $WORK/gobofiles && cp -r $SPIN/gobofiles $WORK/gobofiles
   cd $WORK/gobofiles
   for s in gobo-trash-purge gobo-folder-colour; do bash -n $s; done
   gcc -O2 -Wall -o gobo-trash gobo-trash.c $(pkg-config --cflags --libs gtk+-3.0)
   rm -rf $P && mkdir -p $P/bin $P/share/applications $P/share/file-manager/actions $P/Resources
   install -m 755 gobo-trash gobo-trash-purge gobo-folder-colour $P/bin/
   install -m 644 gobo-trash.desktop $P/share/applications/gobo-trash.desktop
   install -m 644 gobo-folder-colour.action.desktop $P/share/file-manager/actions/gobo-folder-colour.desktop
   echo "GoboRefined file tools: Trash window with automatic clean-up, folder colours for PCManFM." > $P/Resources/Description
   ln -sfn $V /Programs/GoboFiles/Current
   SymlinkProgram GoboFiles $V | tail -n 1
   ;;
dnsmasq)
   # 0.8.2: DHCP (and DNS forwarding) for the devices that join the Wi-Fi hotspot (Settings >
   # Hotspot; started by gobo-hotspot with its own command line, never as a system service).
   # Plain Makefile, no dependencies. Source: https://thekelleys.org.uk/dnsmasq/dnsmasq-2.91.tar.xz
   V=2.91 P=/Programs/Dnsmasq/2.91
   need dnsmasq-$V.tar.xz
   rm -rf $WORK/dnsmasq-$V && tar xf $SRC/dnsmasq-$V.tar.xz -C $WORK
   cd $WORK/dnsmasq-$V
   make -j2 PREFIX=$P COPTS="-O2"
   rm -rf $P && make install PREFIX=$P
   mkdir -p $P/Resources $P/share/doc
   cp COPYING $P/share/doc/dnsmasq-COPYING
   echo "dnsmasq: small DHCP and DNS server (gives addresses to devices on the Wi-Fi hotspot)." > $P/Resources/Description
   ln -sfn $V /Programs/Dnsmasq/Current
   SymlinkProgram Dnsmasq $V | tail -n 1
   ;;
l3afpad)
   # 0.8.1: plain text editor (GTK 3 fork of Leafpad), the default for text/plain (apply.sh)
   unpack l3afpad-0.8.18.1.11.tar.gz
   ./autogen.sh
   ./configure --prefix=/Programs/L3afpad/0.8.18.1.11
   finish L3afpad 0.8.18.1.11 "L3afpad: simple GTK 3 text editor (Leafpad fork)."
   ;;
linux-firmware)
   # 0.8.4: current firmware collection from kernel.org (017.01 ships linux-firmware 20250309):
   # newer Wi-Fi, Bluetooth, GPU and audio firmware for recent laptops. Installed the way its own
   # "make install-zst" does (copy-firmware.sh --zstd: the 6.12 kernel loads .zst firmware), into
   # /Programs/Linux-Firmware/20261019/lib/firmware; build-iso.sh replaces the stock version with it.
   # Left out (not for x86_64 PCs, 476 MB): qcom (Qualcomm phone/ARM SoCs), mellanox (Spectrum
   # switch ASICs), mrvl/prestera (Marvell switches), netronome, qed, liquidio (server NICs),
   # dpaa2 (NXP ARM networking). Files of the stock 20250309 set that upstream has since dropped
   # are kept (copied from the stock image), so nothing the image had goes missing.
   V=20261019 P=/Programs/Linux-Firmware/20261019 OLD=/Programs/Linux-Firmware/20250309-GIT/lib/firmware
   need linux-firmware-$V.tar.xz
   rm -rf $WORK/linux-firmware-$V $P && tar xf $SRC/linux-firmware-$V.tar.xz -C $WORK
   cd $WORK/linux-firmware-$V
   mkdir -p $P/lib/firmware $P/share/doc/linux-firmware
   sh ./copy-firmware.sh --zstd $P/lib/firmware > $WORK/copy-firmware.log 2>&1 ||
      { tail -n 20 $WORK/copy-firmware.log; exit 1; }
   cp -a WHENCE README.md LICENSE* LICENSES $P/share/doc/linux-firmware/ 2>/dev/null ||
      cp -a WHENCE LICEN* $P/share/doc/linux-firmware/
   F=$P/lib/firmware
   rm -rf $F/qcom $F/mellanox $F/mrvl/prestera $F/netronome $F/qed $F/liquidio $F/dpaa2
   # links that pointed into the trees left out
   find $F -xtype l -delete
   # Sound Open Firmware comes from sof-bin (step sof-firmware), the regulatory database from
   # wireless-regdb (GoboSpin): never two versions of the same file
   rm -rf $F/intel/sof $F/intel/sof-tplg $F/intel/sof-ipc4 $F/intel/sof-ipc4-lib $F/intel/sof-ipc4-tplg $F/intel/sof-ace-tplg
   rm -f $F/regulatory.db $F/regulatory.db.p7s $F/regulatory.db.zst $F/regulatory.db.p7s.zst
   if [ -d $OLD ]
   then
      kept=0
      while IFS= read -r f
      do
         [ -e "$F/$f" ] || [ -e "$F/$f.zst" ] || [ -e "$F/${f%.zst}" ] || [ -L "$F/$f" ] || { mkdir -p "$F/$(dirname "$f")"; cp -a "$OLD/$f" "$F/$f"; kept=$((kept + 1)); }
      done < <(cd $OLD && find . \( -type f -o -type l \) ! -path './qcom/*' ! -path './mellanox/*' ! -path './mrvl/prestera/*' \
                  ! -path './netronome/*' ! -path './qed/*' ! -path './liquidio/*' ! -path './dpaa2/*' ! -path './intel/sof*' | sed 's#^\./##')
      echo "kept $kept files of the stock 20250309 set that upstream dropped"
      find $F -xtype l -delete
   fi
   chown -R root:root $P
   resources Linux-Firmware $V "Firmware for devices supported by the Linux kernel (linux-firmware from kernel.org)" \
      "Various redistributable licences (see share/doc/linux-firmware/WHENCE)" "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"
   du -sh $P
   ;;
sof-firmware)
   # 0.8.4: Sound Open Firmware for Intel laptops (Tiger Lake and newer need it for the built-in
   # speakers/microphones; 017.01 ships SOF 1.4.2 from 2020, which has no Tiger Lake firmware).
   # Official release tarball of thesofproject/sof-bin, installed the way its install.sh does
   # (every sof* tree under lib/firmware/intel, relative links kept: IPC3 "sof"/"sof-tplg" and
   # IPC4 "sof-ipc4"/"sof-ipc4-lib"/"sof-ipc4-tplg"/"sof-ace-tplg"); the debugging tools are
   # left out. Data only. Replaces the stock SOF-Firmware 1.4.2 in the image (build-iso.sh).
   V=2026.09.2 P=/Programs/SOF-Firmware/2026.09.2
   need sof-bin-$V.tar.gz
   rm -rf $WORK/sof-bin-$V $P && tar xzf $SRC/sof-bin-$V.tar.gz -C $WORK
   mkdir -p $P/lib/firmware/intel $P/share/doc/sof-firmware
   for d in $WORK/sof-bin-$V/sof*
   do cp -a $d $P/lib/firmware/intel/
   done
   for f in LICENCE.Intel LICENCE.NXP Notice.NXP README.Intel README.md manifest.txt
   do install -m 644 $WORK/sof-bin-$V/$f $P/share/doc/sof-firmware/
   done
   # what Tiger Lake laptops with an HDA codec load (kernel 6.12: IPC3 by default)
   for f in sof/sof-tgl.ri sof-tplg/sof-hda-generic-2ch.tplg sof-ipc4/tgl/sof-tgl.ri sof-ace-tplg
   do [ -e $P/lib/firmware/intel/$f ] || { echo "sof-bin: $f missing"; exit 1; }
   done
   chown -R root:root $P
   resources SOF-Firmware $V "Sound Open Firmware (Intel audio DSP firmware and topologies)" \
      "BSD-3-Clause (Intel/NXP firmware release licence, see share/doc/sof-firmware)" "https://github.com/thesofproject/sof-bin"
   du -sh $P
   ;;
sbc)
   # 0.8.5: the SBC codec library (Bluetooth A2DP audio), needed by PulseAudio's Bluetooth modules.
   # (Steps added in 0.8.5, after sof-firmware: sbc pulseaudio-bluetooth; the list in the header
   # is left as it was because the header is part of every step's hash in build/build.sh.)
   unpack sbc-2.0.tar.xz
   gobo_configure SBC 2.0 --disable-tester
   finish SBC 2.0 "SBC (Bluetooth low-complexity subband codec) library."
   ;;
pulseaudio-bluetooth)
   # 0.8.5: the Bluetooth modules of PulseAudio 13.0. The stock PulseAudio 13.0 (UseFlags "bluez")
   # was built without them because the SBC library was missing. Same version and the same layout
   # as the stock program (prefix /usr = /System/Index, modules in /usr/lib/pulse-13.0/modules,
   # the same RPATH); only the Bluetooth modules are built and kept. They go into
   # /Programs/PulseAudio-Bluetooth/13.0 (not linked with SymlinkProgram: /System/Index/lib/pulse-13.0
   # is a link to the stock program); build-iso.sh copies them next to the stock modules.
   unpack pulseaudio-13.0.tar.xz
   CFLAGS="$CF" ./configure --prefix=/usr --sysconfdir=/System/Settings --localstatedir=/Data/Variable \
      --enable-bluez5 --enable-bluez5-native-headset --disable-bluez5-ofono-headset > $WORK/pa-configure.out
   grep -E 'Enable BlueZ 5|native headset|Enable D-Bus' $WORK/pa-configure.out
   grep -q 'Enable BlueZ 5: *yes' $WORK/pa-configure.out || { echo "configure did not enable BlueZ 5"; exit 1; }
   BT="libbluez5-util.la module-bluez5-discover.la module-bluez5-device.la module-bluetooth-discover.la module-bluetooth-policy.la"
   # (the ORC header is a generated source; make builds it only for "all", so first)
   make -C src pulsecore/svolume-orc-gen.h
   make -C src -j2 $BT
   D=$WORK/pa-dest P=/Programs/PulseAudio-Bluetooth/13.0
   rm -rf $D $P
   make -C src install-modlibexecLTLIBRARIES DESTDIR=$D modlibexec_LTLIBRARIES="$BT"
   mkdir -p $P/lib/pulse-13.0/modules $P/share/doc/pulseaudio-bluetooth
   for m in $BT
   do
      f=$D/usr/lib/pulse-13.0/modules/${m%.la}.so
      [ -f $f ] || { echo "missing $f"; exit 1; }
      install -m 755 $f $P/lib/pulse-13.0/modules/
   done
   # the stock modules' search path (RPATH there; gcc 14's linker writes it as RUNPATH):
   # libbluez5-util.so is found next to the modules; libsbc linked
   readelf -d $P/lib/pulse-13.0/modules/module-bluez5-device.so | grep -q 'path: \[/usr/lib/pulseaudio:/usr/lib/pulse-13.0/modules\]' ||
      { echo "unexpected RPATH"; readelf -d $P/lib/pulse-13.0/modules/module-bluez5-device.so; exit 1; }
   readelf -d $P/lib/pulse-13.0/modules/libbluez5-util.so | grep -q 'libsbc.so.1' || { echo "libbluez5-util without libsbc"; exit 1; }
   install -m 644 LICENSE LGPL $P/share/doc/pulseaudio-bluetooth/
   mkdir -p $P/Resources
   echo x86_64 > $P/Resources/Architecture
   printf 'PulseAudio 13.0\nSBC 2.0\n' > $P/Resources/Dependencies
   printf '[Name] PulseAudio-Bluetooth\n[Summary] %s\n[License] LGPL-2.1-or-later\n[Homepage] https://www.freedesktop.org/wiki/Software/PulseAudio/\n' \
      "Bluetooth modules (A2DP, HSP) of PulseAudio 13.0, built for the stock PulseAudio" > $P/Resources/Description
   ln -sfn 13.0 /Programs/PulseAudio-Bluetooth/Current
   ls -l $P/lib/pulse-13.0/modules
   ;;
glibc)
   # 0.9.7: the GNU C library 2.38 (017.01 has 2.30), so that current ready-made programs
   # (AppImages, VS Code, Steam ...: glibc >= 2.34) run. The 2.38 release plus the fixes of its stable
   # branch (spin/patches/glibc-2.38-branch-*.patch: CVE-2023-4911 and many more), configured like the
   # stock 2.30 (gobolinux/Recipes Glibc/2.30: prefix /usr, sysconfdir /System/Settings, slibdir /lib)
   # so every compiled-in path stays where 2.30 has it. libcrypt is built (--enable-crypt): logins
   # read the same $6$ hashes. Installed to /Programs/Glibc/2.38 ONLY: the build root keeps running
   # its own 2.30 (no SymlinkProgram, Current stays); spin/build-iso.sh switches the image over.
   V=2.38 P=/Programs/Glibc/2.38 OLD=/Programs/Glibc/2.30
   PATCH=$(ls $SPIN/patches/glibc-2.38-branch-*.patch)
   [ "$(readlink /Programs/Glibc/Current)" = 2.30 ] && [ -d $OLD/lib ] || { echo "the build root's C library is not the stock 2.30"; exit 1; }
   [ -f "$PATCH" ] || { echo "no glibc branch patch in $SPIN/patches"; exit 1; }
   unpack glibc-$V.tar.xz
   patch -p1 -s < "$PATCH"
   # Gobo: /usr/include/net and scsi are links into the index (installing goes to an install root,
   # nothing is clobbered); FHS paths as in the recipe's glibc-2.30-fhs-1.patch
   sed -i 's,test -L \${ac_prefix}/include/\(net\|scsi\),false,' sysdeps/unix/sysv/linux/configure
   grep -q 'include/net is a symlink' sysdeps/unix/sysv/linux/configure && ! grep -q 'test -L ${ac_prefix}/include' sysdeps/unix/sysv/linux/configure ||
      { echo "the include/net check was not switched off"; exit 1; }
   sed -i 's,"/var/db/nscd/,"/var/cache/nscd/,' nscd/nscd.h
   sed -i 's,^VAR_DB = /var/db$,VAR_DB = /var/lib/nss_db,' nss/db-Makefile
   sed -i 's,"/var/db/","/var/lib/nss_db/",' sysdeps/generic/paths.h sysdeps/unix/sysv/linux/paths.h
   sed -i 's,^vardbdir = \$(localstatedir)/db$,vardbdir = $(localstatedir)/lib/nss_db,' Makeconfig
   ! grep -q '/var/db' nscd/nscd.h sysdeps/unix/sysv/linux/paths.h || { echo "FHS path change failed"; exit 1; }
   mkdir _build && cd _build
   GB=$(pwd)
   # (the image's "ld" is gold: glibc needs GNU ld)
   CC="gcc -fuse-ld=bfd" LD=ld.bfd CFLAGS="-O2 -pipe" CXXFLAGS="-O2 -pipe" \
   ../configure --prefix=/usr --sysconfdir=/System/Settings --localstatedir=/var --libexecdir=/usr/lib \
      --enable-kernel=3.2 --with-headers=/Programs/Linux-Headers/Current/include \
      --enable-stack-protector=strong --disable-profile --disable-werror --enable-crypt \
      libc_cv_slibdir=/lib
   NJ=$(nproc)
   make -j$NJ
   # quick checks (not the whole test suite: hours, and parts need a container setup)
   # glibc's own tests of libcrypt (a FAIL stops the build; the comparison below is the main gate)
   make -C ../crypt objdir=$GB check > /Data/Build/glibc-check-crypt.log 2>&1 || echo "make check in crypt returned an error (see the summary)"
   if [ -f crypt/subdir-tests.sum ]
   then
      cut -d: -f1 crypt/subdir-tests.sum | sort | uniq -c
      ! grep -q '^FAIL:' crypt/subdir-tests.sum || { grep '^FAIL:' crypt/subdir-tests.sum; tail -n 30 /Data/Build/glibc-check-crypt.log; echo "glibc crypt tests failed"; exit 1; }
   else echo "NOTE: the crypt tests did not run (no crypt/subdir-tests.sum); log: /Data/Build/glibc-check-crypt.log"; tail -n 15 /Data/Build/glibc-check-crypt.log
   fi
   ./testrun.sh /System/Index/bin/bash -c 'echo "new C library runs bash"'
   ./testrun.sh /System/Index/bin/python3 -c 'import sys; print("new C library runs python", sys.version.split()[0])'
   h_new=$(./testrun.sh /System/Index/bin/python3 -c 'import crypt; print(crypt.crypt("Gobo test 1", "$6$gobosalt1234567"))')
   h_ref=$(openssl passwd -6 -salt gobosalt1234567 'Gobo test 1')
   [ -n "$h_ref" ] && [ "$h_new" = "$h_ref" ] || { echo "libcrypt 2.38 gives another SHA-512 hash: '$h_new' vs '$h_ref'"; exit 1; }
   echo "libcrypt 2.38: SHA-512 crypt matches openssl"
   ./testrun.sh ./elf/ldconfig -V | head -n 1
   DEST=/Data/Build/glibc-dest
   rm -rf $DEST && mkdir -p $DEST
   make install install_root=$DEST
   make -j$NJ localedata/install-locales install_root=$DEST > /Data/Build/glibc-locales.log 2>&1 || { tail -n 30 /Data/Build/glibc-locales.log; exit 1; }
   # the gconv module cache (make install does not write it; 2.30 has one): iconvconfig of the new
   # build, on the install root's usr/lib/gconv
   ./testrun.sh ./iconv/iconvconfig --prefix=$DEST
   [ -f $DEST/usr/lib/gconv/gconv-modules.cache ] || { echo "iconvconfig wrote no gconv-modules.cache"; exit 1; }
   # lay out like the stock 2.30 program
   rm -rf $P && mkdir -p $P/bin $P/lib $P/Resources
   cp -a $DEST/lib/. $P/lib/
   cp -a $DEST/usr/lib/. $P/lib/
   for d in usr/bin usr/sbin sbin bin
   do [ -d $DEST/$d ] && cp -a $DEST/$d/. $P/bin/
   done
   cp -a $DEST/usr/include $P/include
   cp -a $DEST/usr/share $P/share
   # library links of the install root (../../lib/libX.so.N) become links inside lib/
   find $P/lib -maxdepth 1 -type l | while read -r l
   do t=$(readlink "$l"); case "$t" in */*) ln -sfn "$(basename "$t")" "$l" ;; esac
   done
   # (bin/ld.so -> ../../lib/ld-linux-x86-64.so.2 in the install root)
   find $P/bin -maxdepth 1 -type l | while read -r l
   do t=$(readlink "$l"); case "$t" in ../../lib/*) ln -sfn "../lib/${t#../../lib/}" "$l" ;; esac
   done
   ln -sfn ld-linux-x86-64.so.2 $P/lib/ld-lsb-x86-64.so.3
   dangling=$(find $P -xtype l | head -n 5)
   [ -z "$dangling" ] || { echo "dangling links in $P: $dangling"; exit 1; }
   # the linker scripts name /lib/... and /usr/lib/... (links to /System/Index/lib), as in 2.30
   grep -q 'GROUP ( /lib/libc.so.6 /usr/lib/libc_nonshared.a' $P/lib/libc.so || { echo "unexpected libc.so linker script"; cat $P/lib/libc.so; exit 1; }
   # debug info off the shared libraries and programs (2.30 is stripped the same way)
   find $P/bin $P/lib -type f \( -name '*.so*' -o -perm -u+x \) | while read -r f
   do if [ "$(head -c 4 "$f" | tail -c 3)" = ELF ]; then strip --strip-debug "$f" || echo "could not strip $f"; fi
   done
   find $P/lib -maxdepth 1 -name '*.a' -exec strip --strip-debug {} \; 2>/dev/null || true
   for f in ld-linux-x86-64.so.2 libc.so.6 libm.so.6 libcrypt.so.1 libpthread.so.0 libdl.so.2 librt.so.1 libresolv.so.2 libnss_files.so.2 libnss_dns.so.2 libnss_db.so.2 libnss_compat.so.2 libutil.so.1 libanl.so.1
   do [ -e $P/lib/$f ] || { echo "glibc 2.38: lib/$f missing"; exit 1; }
   done
   [ -e $P/lib/libnsl.so.1 ] || echo "NOTE: glibc 2.38 has no libnsl.so.1 (2.30 had it; spin/build-iso.sh checks that nothing needs it)"
   for f in ldd ldconfig locale localedef iconv getent getconf
   do [ -x $P/bin/$f ] || { echo "glibc 2.38: bin/$f missing"; exit 1; }
   done
   [ -s $P/lib/locale/locale-archive ] && [ -f $P/lib/gconv/gconv-modules.cache ] || { echo "no locale archive or gconv cache"; ls $P/lib/locale $P/lib/gconv | head; exit 1; }
   ls -la $P/lib/ld-linux-x86-64.so.2 $P/lib/libc.so.6 $P/lib/libcrypt.so.1
   # locales: the archive is read with the new library
   n=$($GB/testrun.sh $GB/locale/localedef --list-archive $P/lib/locale/locale-archive | tee /Data/Build/glibc-locales.list | wc -l)
   grep -qx en_US.utf8 /Data/Build/glibc-locales.list && grep -qx pl_PL.utf8 /Data/Build/glibc-locales.list || { echo "en_US.utf8 / pl_PL.utf8 not in the archive"; exit 1; }
   echo "locales in the archive: $n"
   # Resources and settings as in 2.30 (Settings are shared: ld.so.conf, nsswitch.conf, rpc)
   mkdir -p $P/Resources/Defaults/Settings
   for f in ld.so.conf nsswitch.conf rpc
   do cp -a $OLD/Resources/Defaults/Settings/$f $P/Resources/Defaults/Settings/
   done
   cp -a $OLD/Resources/Unmanaged $OLD/Resources/UnmanagedFiles $P/Resources/
   echo x86_64 > $P/Resources/Architecture
   printf 'BinUtils 2.33.1\nGCC 14.2.0\nLinux-Headers 5.4.15\n' > $P/Resources/Dependencies
   printf '[Name] Glibc\n[Summary] %s\n[License] LGPL-2.1-or-later\n[Homepage] https://www.gnu.org/software/libc/\n' \
      "The GNU C library 2.38 with the fixes of its stable branch (GoboRefined 0.9.7)" > $P/Resources/Description
   echo "[File] https://ftp.gnu.org/gnu/glibc/glibc-$V.tar.xz" > $P/Resources/PackageSource
   chown -R root:root $P
   rm -rf $DEST
   [ "$(readlink /Programs/Glibc/Current)" = 2.30 ] && [ "$(readlink -f /System/Index/lib/libc.so.6)" = "$(readlink -f $OLD/lib/libc.so.6)" ] ||
      { echo "the build root's own C library changed"; exit 1; }
   du -sh $P $P/lib/locale
   ;;
btrfs-progs)
   # 0.10: the btrfs tools (mkfs.btrfs, btrfs subvolume/property/filesystem, btrfs check) for the
   # btrfs A/B layout (docs/ab-btrfs-plan.md): the installer makes the pool and its subvolumes,
   # gobo-update snapshots and sets subvolumes read-only. The kernel's btrfs is a module of the
   # 6.12 kernel already. Needs libuuid/libblkid (Util-Linux), zlib, LZO, Zstd (all on 017.01);
   # checksums use the built-in code (no crypto library). Zoned support detects itself off
   # (Linux-Headers 5.4 is older than the 5.10 it needs). No btrfs-convert, no Python module,
   # no documentation (would need sphinx). Its udev rules stay inside the program.
   V=7.3 P=/Programs/Btrfs-Progs/7.3
   unpack btrfs-progs-v$V.tar.xz btrfs-progs-v$V
   rm -rf $P
   ./configure --prefix=$P --disable-convert --disable-documentation --disable-python \
      --disable-static --disable-libudev > /Data/Build/btrfs-progs-configure.log 2>&1 ||
      { tail -n 30 /Data/Build/btrfs-progs-configure.log; exit 1; }
   make -j$(nproc) > /Data/Build/btrfs-progs-make.log 2>&1 || { grep -m 5 -B 3 -A 3 'error' /Data/Build/btrfs-progs-make.log; tail -n 30 /Data/Build/btrfs-progs-make.log; exit 1; }
   make install udevdir=$P/lib/udev > /Data/Build/btrfs-progs-install.log 2>&1 || { tail -n 30 /Data/Build/btrfs-progs-install.log; exit 1; }
   ln -sfn $V /Programs/Btrfs-Progs/Current
   mkdir -p $P/Resources $P/doc
   install -m 644 COPYING $P/doc/
   echo x86_64 > $P/Resources/Architecture
   printf 'Util-Linux\nZLib\nLZO\nZstd\n' > $P/Resources/Dependencies
   printf '[Name] Btrfs-Progs\n[Summary] %s\n[License] GPL-2.0-only (libbtrfsutil: LGPL-2.1-or-later)\n[Homepage] https://btrfs.readthedocs.io/\n' \
      "Btrfs file system tools: mkfs.btrfs, btrfs (subvolumes, snapshots, check)" > $P/Resources/Description
   echo "[File] https://mirrors.edge.kernel.org/pub/linux/kernel/people/kdave/btrfs-progs/btrfs-progs-v$V.tar.xz" > $P/Resources/PackageSource
   chown -R root:root $P
   SymlinkProgram Btrfs-Progs $V | tail -n 1
   $P/bin/btrfs --version
   $P/bin/mkfs.btrfs --version | head -n 1
   ;;
rsync)
   # 0.10: rsync, for gobo-update on the btrfs layout (the new version's files are copied over a
   # snapshot of the running one, so files that did not change stay shared). Uses the image's
   # popt, zlib, zstd, lz4, OpenSSL 1.1, ACL and attr libraries; no xxhash (not on 017.01), no man
   # pages (they need a Markdown tool).
   V=3.5.2 P=/Programs/Rsync/3.5.2
   unpack rsync-$V.tar.gz rsync-$V
   rm -rf $P
   ./configure --prefix=$P --sysconfdir=/Programs/Rsync/Settings --disable-xxhash --disable-md2man \
      --without-included-popt --without-included-zlib > /Data/Build/rsync-configure.log 2>&1 ||
      { tail -n 30 /Data/Build/rsync-configure.log; exit 1; }
   make -j$(nproc) > /Data/Build/rsync-make.log 2>&1 || { tail -n 30 /Data/Build/rsync-make.log; exit 1; }
   make install > /Data/Build/rsync-install.log 2>&1 || { tail -n 30 /Data/Build/rsync-install.log; exit 1; }
   ln -sfn $V /Programs/Rsync/Current
   mkdir -p $P/Resources $P/doc
   install -m 644 COPYING $P/doc/
   echo x86_64 > $P/Resources/Architecture
   printf 'Popt\nZLib\nZstd\nLZ4\nOpenSSL\nACL\nAttr\n' > $P/Resources/Dependencies
   printf '[Name] Rsync\n[Summary] %s\n[License] GPL-3.0-or-later\n[Homepage] https://rsync.samba.org/\n' \
      "Fast incremental file copy (used by gobo-update on the btrfs layout)" > $P/Resources/Description
   echo "[File] https://download.samba.org/pub/rsync/src/rsync-$V.tar.gz" > $P/Resources/PackageSource
   chown -R root:root $P
   SymlinkProgram Rsync $V | tail -n 1
   $P/bin/rsync --version | head -n 3
   ;;
libva)
   # 0.10.3: LibVA 2.24.1 (VA-API 1.24) instead of 017.01's 2.7.0 (VA-API 1.7): Chromium/Electron
   # (Chrome, Electron AppImages) refuse VA-API below 1.17 ("Installed VAAPI version is too old").
   # Same library names (libva.so.2, -drm, -x11, -glx), same driver folder (/usr/lib/dri, where
   # 017.01's Mesa 19.3 VA drivers are: nouveau, r600, radeonsi; they still load, VA-API keeps the
   # old driver entry points) and the same /etc/libva.conf as the stock build. No Wayland (017.01
   # has none). The newest release still ships configure (autotools; meson does not work here).
   # Installed and linked in the build root too (libva-utils builds against it); the image step
   # drops 2.7.0 (only FFmpeg 4.2 links libva, through the unchanged sonames).
   V=2.24.1 P=/Programs/LibVA/2.24.1
   unpack libva-$V.tar.bz2 libva-$V
   rm -rf $P
   ./configure --prefix=$P --sysconfdir=/etc --disable-static --enable-drm --enable-x11 --enable-glx \
      --disable-wayland --with-drivers-path=/usr/lib/dri > /Data/Build/libva-configure.log 2>&1 ||
      { tail -n 30 /Data/Build/libva-configure.log; exit 1; }
   grep -q 'Extra window systems .*: drm x11 glx' /Data/Build/libva-configure.log || { tail -n 12 /Data/Build/libva-configure.log; echo "libva: drm/x11/glx not all found"; exit 1; }
   make -j$(nproc) > /Data/Build/libva-make.log 2>&1 || { grep -m 5 -B 3 -A 3 'error' /Data/Build/libva-make.log; tail -n 30 /Data/Build/libva-make.log; exit 1; }
   make install > /Data/Build/libva-install.log 2>&1 || { tail -n 30 /Data/Build/libva-install.log; exit 1; }
   rm -f $P/lib/*.la
   mkdir -p $P/Resources $P/doc
   install -m 644 COPYING $P/doc/
   echo x86_64 > $P/Resources/Architecture
   printf 'LibDRM\nLibX11\nLibXext\nLibXfixes\nLibGLVnd\n' > $P/Resources/Dependencies
   printf '[Name] LibVA\n[Summary] %s\n[License] MIT\n[Homepage] https://github.com/intel/libva\n' \
      "Video Acceleration API (VA-API) library" > $P/Resources/Description
   echo "[File] https://github.com/intel/libva/releases/download/$V/libva-$V.tar.bz2" > $P/Resources/PackageSource
   chown -R root:root $P
   # the stock 2.7.0's index links go first, so that nothing is left pointing at it
   find /System/Index -xdev -lname '/Programs/LibVA/2.7.0/*' -print0 > /Data/Build/libva-old-links
   xargs -0 -r rm -f < /Data/Build/libva-old-links
   ln -sfn $V /Programs/LibVA/Current
   SymlinkProgram LibVA $V | tail -n 1
   [ "$(readlink -f /System/Index/lib/libva.so.2)" = "$P/lib/libva.so.2.2400.0" ] || { echo "libva.so.2 is not $V's"; exit 1; }
   grep -q 'VA_MINOR_VERSION *24' $P/include/va/va_version.h || { echo "not VA-API 1.24"; exit 1; }
   ;;
libva-utils)
   # 0.10.3: vainfo (and the VA-API test programs of libva-utils) to check video acceleration:
   # "vainfo" shows the driver and what it can decode. Built against LibVA 2.24.1 (step libva).
   V=2.24.0 P=/Programs/LibVA-Utils/2.24.0
   [ "$(readlink /Programs/LibVA/Current)" = 2.24.1 ] || { echo "LibVA 2.24.1 is not built (step libva)"; exit 1; }
   unpack libva-utils-$V.tar.bz2 libva-utils-$V
   rm -rf $P
   ./configure --prefix=$P --enable-drm --enable-x11 --disable-wayland --disable-tests \
      > /Data/Build/libva-utils-configure.log 2>&1 || { tail -n 30 /Data/Build/libva-utils-configure.log; exit 1; }
   make -j$(nproc) > /Data/Build/libva-utils-make.log 2>&1 || { grep -m 5 -B 3 -A 3 'error' /Data/Build/libva-utils-make.log; tail -n 30 /Data/Build/libva-utils-make.log; exit 1; }
   make install > /Data/Build/libva-utils-install.log 2>&1 || { tail -n 30 /Data/Build/libva-utils-install.log; exit 1; }
   ln -sfn $V /Programs/LibVA-Utils/Current
   mkdir -p $P/Resources $P/doc
   install -m 644 COPYING $P/doc/
   echo x86_64 > $P/Resources/Architecture
   printf 'LibVA >= 2.24.1\nLibDRM\nLibX11\n' > $P/Resources/Dependencies
   printf '[Name] LibVA-Utils\n[Summary] %s\n[License] MIT\n[Homepage] https://github.com/intel/libva-utils\n' \
      "VA-API tools: vainfo (video acceleration driver and profiles) and test programs" > $P/Resources/Description
   echo "[File] https://github.com/intel/libva-utils/releases/download/$V/libva-utils-$V.tar.bz2" > $P/Resources/PackageSource
   chown -R root:root $P
   SymlinkProgram LibVA-Utils $V | tail -n 1
   lib=$(ldd $P/bin/vainfo | awk '$1 == "libva.so.2" { print $3 }')
   [ -n "$lib" ] && [ "$(readlink -f "$lib")" = /Programs/LibVA/2.24.1/lib/libva.so.2.2400.0 ] || { ldd $P/bin/vainfo; echo "vainfo does not use LibVA 2.24.1"; exit 1; }
   ;;
########## stage 2 ##########################################################################
# The steps below run in build/build.sh's stage-2 build root (STEPS2): the stage-1 build root with
# its C library switched to Glibc 2.38 (spin/glibc-switch.sh) and gcc's include-fixed made again for
# the 2.38 headers. They are build tools for the graphics stack (0.10.4: Mesa); none is in the image.
llvm)
   # Build-environment jump: llvm.org's prebuilt LLVM + clang 23.1.6 (needs GLIBC_2.34, so stage 2 only).
   # Mesa (0.10.4) needs LLVM >= 18 for radeonsi/radv and clang + libclang-cpp for its CLC shaders.
   # (llvm.org packs it with a 1 GiB zstd window: zstd 1.4.4 needs --memory to unpack it.)
   # Unpacked as a Gobo program; in this root the index links of the stock LLVM 9.0.1 make room for it
   # (llvm-config, libLTO, headers), the 9.0.1 folder itself stays.
   . $SPIN/stage2-lib.sh
   stage2_check
   V=23.1.6 P=/Programs/LLVM/23.1.6 T=LLVM-23.1.6-Linux-X64.tar.zst
   need $T
   top=$(zstd -dc --memory=2048MB $SRC/$T 2>/dev/null | tar tf - 2>/dev/null | head -n 1 || true)
   [ "${top%%/*}" = LLVM-$V-Linux-X64 ] || { echo "unexpected first entry in $T: '$top'"; exit 1; }
   rm -rf $P && mkdir -p $P
   zstd -dcq --memory=2048MB $SRC/$T | tar xf - -C $P --strip-components=1 --no-same-owner
   [ -x $P/bin/clang ] && [ -x $P/bin/llvm-config ] && [ -d $P/include/llvm ] || { ls $P $P/bin | head -n 30; echo "LLVM $V: clang/llvm-config/headers missing"; exit 1; }
   stage2_resources LLVM $V "LLVM $V and clang (the llvm.org release build): compilers and libraries for building Mesa" \
      "Apache-2.0 WITH LLVM-exception" https://llvm.org/ \
      https://github.com/llvm/llvm-project/releases/download/llvmorg-$V/$T "Glibc >= 2.34" GCC
   # The static LLVM wants a static zstd, which 017.01 does not have: "llvm-config --system-libs" names the
   # build machine's /usr/lib/x86_64-linux-gnu/libzstd.a (compiled in), and LLVM's cmake files need the
   # target zstd::libzstd_static (their Findzstd looks for libzstd.a). Two added files in the program, a
   # linker script lib/libzstd.a and a link lib/x86_64-linux-gnu/libzstd.a to it, point both at 017.01's
   # libzstd.so.1 (1.4.4; LLVM uses its 1.4 API): programs linking LLVM then need libzstd.so.1, which the
   # image has. SymlinkProgram links them into the index of this root.
   [ "$($P/bin/llvm-config --system-libs)" = "-lrt -ldl -lm -lz /usr/lib/x86_64-linux-gnu/libzstd.a -lxml2" ] ||
      { $P/bin/llvm-config --system-libs; echo "llvm-config --system-libs changed: check the libzstd.a link script"; exit 1; }
   [ -e /System/Index/lib/libzstd.so.1 ] && [ -e /System/Index/lib/libxml2.so ] || { echo "no libzstd.so.1 or libxml2.so in the root"; exit 1; }
   [ ! -e /System/Index/lib/libzstd.a ] || { ls -la /System/Index/lib/libzstd.a; echo "a libzstd.a is already in the index"; exit 1; }
   mkdir -p $P/lib/x86_64-linux-gnu
   printf '/* GoboRefined: the llvm.org LLVM build wants a static zstd; use the system libzstd.so.1 */\nINPUT ( /usr/lib/libzstd.so.1 )\n' > $P/lib/libzstd.a
   ln -sfn ../libzstd.a $P/lib/x86_64-linux-gnu/libzstd.a
   stage2_unlink /Programs/LLVM/9.0.1/
   ln -sfn $V /Programs/LLVM/Current
   SymlinkProgram LLVM $V | tail -n 1
   [ "$(readlink -f /usr/lib/x86_64-linux-gnu/libzstd.a)" = $P/lib/libzstd.a ] && [ "$(readlink -f /usr/lib/libzstd.a)" = $P/lib/libzstd.a ] ||
      { ls -la /usr/lib/libzstd* /usr/lib/x86_64-linux-gnu/ 2>&1 | head; echo "the libzstd.a link script is not linked into the index"; exit 1; }
   # checks
   clang --version | head -n 1 | grep -q "clang version $V" || { clang --version; echo "clang is not $V"; exit 1; }
   [ "$(llvm-config --version)" = $V ] || { echo "llvm-config is not $V"; exit 1; }
   # llvm.org's Linux build is a STATIC LLVM: no libLLVM.so, the LLVM libraries are .a files (Mesa links
   # them into its drivers: meson -Dshared-llvm=disabled). Shared: libclang-cpp.so (clang's C++ API, with
   # its own copy of LLVM), libclang.so (C API), libLTO, liblldb.
   [ "$(llvm-config --shared-mode)" = static ] || echo "NOTE: llvm-config --shared-mode says $(llvm-config --shared-mode)"
   echo "llvm-config: $(llvm-config --shared-mode), libdir $(llvm-config --libdir), $(llvm-config --libs | wc -w) libraries in --libs, targets: $(llvm-config --targets-built)"
   for c in core amdgpu x86 mcjit orcjit bitwriter ipo coroutines lto passes
   do llvm-config --libs $c > /dev/null || { echo "llvm-config does not know the component $c"; exit 1; }
   done
   for f in libLLVMCore.a libLLVMAMDGPUCodeGen.a libLLVMX86CodeGen.a libclangCodeGen.a libclangFrontend.a libclang-cpp.so.23.1 libclang.so.23.1
   do [ -e $P/lib/$f ] || { echo "LLVM $V: lib/$f missing"; exit 1; }
   done
   for f in $P/bin/clang-23 $P/bin/llvm-config $P/lib/libclang-cpp.so.23.1 $P/lib/libclang.so.23.1
   do
      ! ldd "$f" | grep -q 'not found' || { ldd "$f"; echo "$f misses libraries"; exit 1; }
      ! ldd -r "$f" 2>&1 | grep -q 'undefined symbol' || { ldd -r "$f" 2>&1 | grep 'undefined symbol' | head; echo "$f: undefined symbols"; exit 1; }
   done
   echo "libclang-cpp.so.23.1 needs: $(ldd $P/lib/libclang-cpp.so.23.1 | awk '{ print $1 }' | tr '\n' ' ')"
   echo "highest GLIBC_ and GLIBCXX_ versions the LLVM binaries need: $(objdump -T $P/bin/clang-23 $P/lib/libclang-cpp.so.23.1 2>/dev/null | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -n 1) $(objdump -T $P/bin/clang-23 $P/lib/libclang-cpp.so.23.1 2>/dev/null | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -n 1)"
   mkdir -p /Data/Build/work/llvmtest && cd /Data/Build/work/llvmtest
   printf '#include <stdio.h>\n#include <gnu/libc-version.h>\nint main(void) { printf("C by clang, glibc %%s\\n", gnu_get_libc_version()); return 0; }\n' > hello.c
   printf '#include <iostream>\n#include <vector>\n#include <string>\nint main() { std::vector<std::string> v{"C++", "by", "clang"}; for (auto &s : v) std::cout << s << " "; std::cout << __cplusplus << std::endl; }\n' > hello.cpp
   clang -O2 -o hello hello.c && ./hello
   clang++ -O2 -std=c++17 -o hellocpp hello.cpp && ./hellocpp
   # a program linked against the static LLVM, as Mesa will be (llvm-config --libs core)
   printf '#include <llvm/IR/LLVMContext.h>\n#include <llvm/IR/Module.h>\n#include <llvm/Config/llvm-config.h>\n#include <iostream>\nint main() { llvm::LLVMContext c; llvm::Module m("t", c); std::cout << "linked LLVM " << LLVM_VERSION_STRING << std::endl; }\n' > llvmapi.cpp
   g++ -O1 $(llvm-config --cxxflags) -o llvmapi llvmapi.cpp $(llvm-config --ldflags --libs core --system-libs) && ./llvmapi
   ls -la llvmapi
   du -sh $P $P/bin $P/lib $P/include
   du -ch $P/lib/libLLVM*.a | tail -n 1 | sed 's/total/static LLVM libraries (lib\/libLLVM*.a)/'
   ;;
cmake)
   # The prebuilt CMake 3.31.12 from Kitware (017.01 has 3.16.4): the LLVM-based and Khronos builds for
   # Mesa (SPIRV-Tools, SPIRV-LLVM-Translator, glslang) need >= 3.20. Build root only.
   . $SPIN/stage2-lib.sh
   stage2_check
   V=3.31.12 P=/Programs/CMake/3.31.12 T=cmake-3.31.12-linux-x86_64.tar.gz
   need $T
   rm -rf $P && mkdir -p $P
   tar xzf $SRC/$T -C $P --strip-components=1 --no-same-owner
   [ -x $P/bin/cmake ] || { echo "no bin/cmake in $T"; exit 1; }
   stage2_resources CMake $V "Cross-platform build system generator (the Kitware binary release)" \
      "BSD-3-Clause" https://cmake.org/ https://github.com/Kitware/CMake/releases/download/v$V/$T
   stage2_unlink /Programs/CMake/3.16.4/
   ln -sfn $V /Programs/CMake/Current
   SymlinkProgram CMake $V | tail -n 1
   cmake --version | head -n 1 | grep -qx "cmake version $V" || { cmake --version; echo "cmake is not $V"; exit 1; }
   # the way SPIRV-LLVM-Translator finds LLVM (0.10.4): find_package(LLVM CONFIG), link the static libraries
   if [ -d /Programs/LLVM/23.1.6/lib/cmake/llvm ]
   then
      T=/Data/Build/work/cmaketest
      rm -rf $T && mkdir -p $T && cd $T
      printf 'cmake_minimum_required(VERSION 3.20)\nproject(t CXX)\nfind_package(LLVM 23.1 REQUIRED CONFIG)\nmessage(STATUS "LLVM ${LLVM_PACKAGE_VERSION} in ${LLVM_DIR}")\ninclude_directories(${LLVM_INCLUDE_DIRS})\nllvm_map_components_to_libnames(L core support)\nadd_executable(t t.cpp)\ntarget_link_libraries(t ${L})\n' > CMakeLists.txt
      printf '#include <llvm/IR/LLVMContext.h>\n#include <llvm/Config/llvm-config.h>\n#include <iostream>\nint main() { llvm::LLVMContext c; std::cout << "cmake + LLVM " << LLVM_VERSION_STRING << std::endl; }\n' > t.cpp
      cmake -S . -B b > cmake.log 2>&1 || { tail -n 30 cmake.log; exit 1; }
      grep 'LLVM 23' cmake.log
      cmake --build b -j$(nproc) > build.log 2>&1 || { tail -n 30 build.log; exit 1; }
      ./b/t
   fi
   du -sh $P
   ;;
python)
   # Python 3.13.18 (017.01 has 3.8.1): meson >= 1.12 and Mesa 26 need Python >= 3.10. Installed with
   # "altinstall" (python3.13 only): python3 stays the stock 3.8.1, which GoboLinux's own scripts use.
   # Build root only. No PGO/LTO (build time); ensurepip off (packages come from pinned sources).
   . $SPIN/stage2-lib.sh
   stage2_check
   V=3.13.18 P=/Programs/Python/3.13.18
   unpack Python-$V.tar.xz Python-$V
   rm -rf $P
   ./configure --prefix=$P --enable-shared --with-ensurepip=no --without-static-libpython \
      LDFLAGS="-Wl,-rpath,$P/lib" > /Data/Build/python-configure.log 2>&1 || { tail -n 30 /Data/Build/python-configure.log; exit 1; }
   make -j$(nproc) > /Data/Build/python-make.log 2>&1 || { grep -m 5 -B 3 -A 3 'error' /Data/Build/python-make.log; tail -n 30 /Data/Build/python-make.log; exit 1; }
   grep -A 12 -i 'modules were not found\|failed to build\|could not build' /Data/Build/python-make.log | head -n 30 || true
   make altinstall > /Data/Build/python-install.log 2>&1 || { tail -n 30 /Data/Build/python-install.log; exit 1; }
   rm -rf $P/lib/python3.13/test $P/lib/python3.13/idlelib/idle_test
   stage2_resources Python $V "The Python 3.13 interpreter (python3.13; build tool for meson and Mesa)" \
      "PSF-2.0" https://www.python.org/ https://www.python.org/ftp/python/$V/Python-$V.tar.xz OpenSSL ZLib LibFFI
   [ "$(readlink /Programs/Python/Current)" = 3.8.1 ] || ln -sfn 3.8.1 /Programs/Python/Current   # the stock interpreter stays the default
   SymlinkProgram Python $V | tail -n 1
   [ "$(readlink -f /System/Index/bin/python3)" = /Programs/Python/3.8.1/bin/python3.8 ] || { echo "python3 is no longer the stock 3.8.1"; exit 1; }
   # (no _bz2: 017.01 has no libbz2 library, only the bzip2 program; no _tkinter: no Tk. Neither is needed here.)
   python3.13 -c 'import sys, zlib, hashlib, json, ctypes, xml.etree.ElementTree, lzma, sqlite3, decimal; print("Python", sys.version.split()[0], "modules ok")'
   python3.13 -c 'import ssl; print(ssl.OPENSSL_VERSION)' || echo "NOTE: python3.13 has no ssl module (not needed for meson/Mesa)"
   du -sh $P
   ;;
ninja)
   # The ninja build tool 1.13.2, the Linux binary of its release. The stock bin/ninja is a stub of a
   # pip package that is not there (/System/Aliens/PIP/3.8): its index link is replaced. Build root only.
   . $SPIN/stage2-lib.sh
   stage2_check
   V=1.13.2 P=/Programs/Ninja/1.13.2 T=ninja-linux-1.13.2.zip
   need $T
   rm -rf $P && mkdir -p $P/bin
   unzip -q -o $SRC/$T -d $P/bin
   chmod 755 $P/bin/ninja
   stage2_resources Ninja $V "Small build system (the backend of meson)" "Apache-2.0" https://ninja-build.org/ \
      https://github.com/ninja-build/ninja/releases/download/v$V/ninja-linux.zip
   stage2_unlink /System/Aliens/PIP/3.8/bin/ninja
   ln -sfn $V /Programs/Ninja/Current
   SymlinkProgram Ninja $V | tail -n 1
   [ "$(ninja --version)" = $V ] || { echo "ninja is not $V"; exit 1; }
   ;;
meson)
   # Meson 1.12.1 (pure Python), run from its source tree by Python 3.13 (step python): no pip, no
   # setuptools needed. Mesa 26 needs meson >= 1.5 (017.01 has none that works: bin/meson is a stub
   # of a missing pip package, replaced here). Build root only.
   . $SPIN/stage2-lib.sh
   stage2_check
   V=1.12.1 P=/Programs/Meson/1.12.1 PY=/Programs/Python/3.13.18/bin/python3.13
   [ -x $PY ] || { echo "Python 3.13.18 is not built (step python)"; exit 1; }
   [ -x /Programs/Ninja/1.13.2/bin/ninja ] || { echo "Ninja 1.13.2 is not there (step ninja)"; exit 1; }
   unpack meson-$V.tar.gz meson-$V
   rm -rf $P && mkdir -p $P/bin $P/lib/meson $P/doc
   cp -a meson.py mesonbuild $P/lib/meson/
   install -m 644 COPYING $P/doc/
   $PY -m compileall -q $P/lib/meson/mesonbuild > /dev/null
   printf '#!/bin/sh\n# Meson %s, run by Python 3.13 (GoboRefined stage-2 build root)\nexec %s %s/lib/meson/meson.py "$@"\n' $V $PY $P > $P/bin/meson
   chmod 755 $P/bin/meson
   stage2_resources Meson $V "Meson build system (run by Python 3.13)" "Apache-2.0" https://mesonbuild.com/ \
      https://github.com/mesonbuild/meson/releases/download/$V/meson-$V.tar.gz "Python >= 3.10" Ninja
   stage2_unlink /System/Aliens/PIP/3.8/bin/meson
   ln -sfn $V /Programs/Meson/Current
   SymlinkProgram Meson $V | tail -n 1
   [ "$(meson --version)" = $V ] || { echo "meson is not $V"; exit 1; }
   # a tiny project, configured, built and run: once with gcc, once with clang (step llvm)
   T=/Data/Build/work/mesontest
   rm -rf $T && mkdir -p $T && cd $T
   printf "project('hello', 'c', 'cpp', version : '1.0')\nm = meson.get_compiler('c').find_library('m')\nexecutable('hello', 'hello.c', dependencies : m)\nexecutable('hellocpp', 'hello.cpp')\n" > meson.build
   printf '#include <stdio.h>\n#include <math.h>\n#include <gnu/libc-version.h>\nint main(void) { printf("meson C: sqrt(2)=%%.3f glibc %%s\\n", sqrt(2.0), gnu_get_libc_version()); return 0; }\n' > hello.c
   printf '#include <iostream>\nint main() { std::cout << "meson C++ " << __VERSION__ << std::endl; }\n' > hello.cpp
   meson setup build-gcc > meson-gcc.log 2>&1 || { tail -n 30 meson-gcc.log; exit 1; }
   meson compile -C build-gcc && ./build-gcc/hello && ./build-gcc/hellocpp
   if command -v clang > /dev/null
   then
      CC=clang CXX=clang++ meson setup build-clang > meson-clang.log 2>&1 || { tail -n 30 meson-clang.log; exit 1; }
      ninja -C build-clang && ./build-clang/hello && ./build-clang/hellocpp
   fi
   ;;
########## stage 2: the graphics stack (0.10.4) #############################################
# Mesa 26.3.1 and what it needs. Build tools (Python modules, SPIRV-Headers/-Tools, the SPIR-V/LLVM
# translator, glslang, Vulkan-Headers) stay in the build root. LibDRM, LibGLVnd, Mesa, Vulkan-Loader,
# Vulkan-Tools and Mesa-Demos go into the image: spin/build-iso.sh copies them from the stage-2
# root (EXTRA2) and they replace 017.01's LibDRM 2.4.100, LibGLVnd 1.2.0 and Mesa 19.3.3.
# Every step logs to /Data/Build/<step>-<part>.log in the stage-2 root; s2run shows the errors.
# Linker: 017.01's "ld" is GNU gold 2.33.1. Gold resolves a call through an undefined weak hidden
# symbol to the library's own load address instead of 0 (Mesa's Vulkan entry-point tables: vulkaninfo
# crashed at libvulkan_intel.so+0x47; a 5-line test shows the same: gold gives the base address, ld.bfd
# gives 0). The steps whose programs go into the image link with ld.bfd (LDFLAGS=-fuse-ld=bfd).
pymods)
   # The Python modules Mesa's build runs with (mako; MarkupSafe for mako; PyYAML; packaging), pure
   # Python, unpacked into Python 3.13's site-packages (that Python has no pip). Build root only.
   . $SPIN/stage2-lib.sh
   stage2_check
   PY=/Programs/Python/3.13.18/bin/python3.13
   [ -x $PY ] || { echo "Python 3.13.18 is not built (step python)"; exit 1; }
   SP=$($PY -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
   [ "$SP" = /Programs/Python/3.13.18/lib/python3.13/site-packages ] || { echo "unexpected site-packages: $SP"; exit 1; }
   need mako-1.4.3-py3-none-any.whl markupsafe-3.0.4.tar.gz pyyaml-6.0.3.tar.gz packaging-26.3-py3-none-any.whl
   rm -rf $SP/mako $SP/mako-*.dist-info $SP/markupsafe $SP/yaml $SP/packaging $SP/packaging-*.dist-info
   unzip -q -o $SRC/mako-1.4.3-py3-none-any.whl -d $SP
   unzip -q -o $SRC/packaging-26.3-py3-none-any.whl -d $SP
   tar xzf $SRC/markupsafe-3.0.4.tar.gz -C $WORK
   cp -r $WORK/markupsafe-3.0.4/src/markupsafe $SP/
   rm -f $SP/markupsafe/_speedups.c   # its C speed-up is optional: the pure Python code is used
   tar xzf $SRC/pyyaml-6.0.3.tar.gz -C $WORK
   cp -r $WORK/pyyaml-6.0.3/lib/yaml $SP/
   chown -R root:root $SP/mako $SP/markupsafe $SP/yaml $SP/packaging $SP/mako-*.dist-info $SP/packaging-*.dist-info
   $PY -m compileall -q $SP/mako $SP/markupsafe $SP/yaml $SP/packaging > /dev/null
   $PY -c 'import mako, markupsafe, yaml, packaging; from packaging.version import Version; from mako.template import Template
assert Version(mako.__version__) >= Version("0.8.0")
print("mako", mako.__version__, "yaml", yaml.__version__, "packaging", packaging.__version__, Template("${x}").render(x="(mako renders)"))'
   ;;
spirv-tools)
   # SPIRV-Headers (a commit of 2026-10 that SPIRV-LLVM-Translator v23.1.3 asks for; newer than the
   # Vulkan SDK 1.4.363 tag) and SPIRV-Tools of the Vulkan SDK 1.4.363 (Mesa: >= 2024.1, for its CLC
   # shaders). Static libraries only reach Mesa's build-time compiler (mesa_clc). Build root only.
   . $SPIN/stage2-lib.sh
   stage2_check
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   HC=cb42dec3830d3ac67fa449ecdc0c0f73d5e74498 HV=1.4.363.0-git-cb42dec PH=/Programs/SPIRV-Headers/1.4.363.0-git-cb42dec
   V=1.4.363.0 P=/Programs/SPIRV-Tools/1.4.363.0 PY=/Programs/Python/3.13.18/bin/python3.13
   unpack SPIRV-Headers-$HC.tar.gz SPIRV-Headers-$HC
   rm -rf $PH
   s2run /Data/Build/spirv-headers-cmake.log cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=$PH -DCMAKE_INSTALL_LIBDIR=lib \
      -DSPIRV_HEADERS_ENABLE_TESTS=OFF -DSPIRV_HEADERS_ENABLE_INSTALL=ON
   s2run /Data/Build/spirv-headers-install.log sh -c 'cmake --build build && cmake --install build'
   mkdir -p $PH/doc && install -m 644 LICENSE $PH/doc/
   stage2_resources SPIRV-Headers $HV "SPIR-V headers (Khronos; build root only)" "MIT" \
      https://github.com/KhronosGroup/SPIRV-Headers https://github.com/KhronosGroup/SPIRV-Headers/archive/$HC.tar.gz
   ln -sfn $HV /Programs/SPIRV-Headers/Current
   SymlinkProgram SPIRV-Headers $HV | tail -n 1
   [ -f $PH/include/spirv/unified1/spirv.hpp ] || { echo "SPIRV-Headers: no include/spirv/unified1/spirv.hpp"; exit 1; }
   unpack SPIRV-Tools-vulkan-sdk-$V.tar.gz SPIRV-Tools-vulkan-sdk-$V
   rm -rf $P
   s2run /Data/Build/spirv-tools-cmake.log cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P \
      -DCMAKE_INSTALL_LIBDIR=lib -DSPIRV-Headers_SOURCE_DIR=$PH -DSPIRV_SKIP_TESTS=ON -DSPIRV_WERROR=OFF \
      -DSPIRV_TOOLS_BUILD_STATIC=ON -DBUILD_SHARED_LIBS=OFF -DPython3_EXECUTABLE=$PY
   s2run /Data/Build/spirv-tools-build.log cmake --build build -j$(nproc)
   s2run /Data/Build/spirv-tools-install.log cmake --install build
   mkdir -p $P/doc && install -m 644 LICENSE $P/doc/
   stage2_resources SPIRV-Tools $V "SPIR-V tools and libraries (Khronos, Vulkan SDK $V; build root only)" "Apache-2.0" \
      https://github.com/KhronosGroup/SPIRV-Tools https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/vulkan-sdk-$V.tar.gz SPIRV-Headers
   ln -sfn $V /Programs/SPIRV-Tools/Current
   SymlinkProgram SPIRV-Tools $V | tail -n 1
   [ -f $P/lib/libSPIRV-Tools.a ] && [ -f $P/lib/libSPIRV-Tools-opt.a ] || { ls $P/lib; echo "SPIRV-Tools: static libraries missing"; exit 1; }
   echo "pkg-config SPIRV-Tools $(pkg-config --modversion SPIRV-Tools), $(spirv-val --version | head -n 1)"
   ;;
spirv-translator)
   # SPIRV-LLVM-Translator v23.1.3 (LLVM 23.1, step llvm): Mesa's CLC compiler (mesa_clc, needed by
   # iris, crocus and anv) turns OpenCL C into SPIR-V with it. A static library, build root only.
   . $SPIN/stage2-lib.sh
   stage2_check
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   V=23.1.3 P=/Programs/SPIRV-LLVM-Translator/23.1.3 PH=/Programs/SPIRV-Headers/1.4.363.0-git-cb42dec
   [ -f $PH/include/spirv/unified1/spirv.hpp ] || { echo "SPIRV-Headers missing (step spirv-tools)"; exit 1; }
   [ "$(llvm-config --version)" = 23.1.6 ] || { echo "LLVM 23.1.6 is not the LLVM here (step llvm)"; exit 1; }
   unpack SPIRV-LLVM-Translator-$V.tar.gz SPIRV-LLVM-Translator-$V
   rm -rf $P
   s2run /Data/Build/spirv-translator-cmake.log cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P \
      -DCMAKE_INSTALL_LIBDIR=lib -DLLVM_DIR=/Programs/LLVM/23.1.6/lib/cmake/llvm -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR=$PH \
      -DLLVM_SPIRV_INCLUDE_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DCCACHE_ALLOWED=OFF
   s2run /Data/Build/spirv-translator-build.log cmake --build build -j$(nproc)
   s2run /Data/Build/spirv-translator-install.log cmake --install build
   mkdir -p $P/doc && install -m 644 LICENSE.TXT $P/doc/
   stage2_resources SPIRV-LLVM-Translator $V "LLVM/SPIR-V translator for LLVM 23.1 (Khronos; build root only)" \
      "Apache-2.0 WITH LLVM-exception" https://github.com/KhronosGroup/SPIRV-LLVM-Translator \
      https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive/refs/tags/v$V.tar.gz "LLVM 23.1" SPIRV-Headers
   ln -sfn $V /Programs/SPIRV-LLVM-Translator/Current
   SymlinkProgram SPIRV-LLVM-Translator $V | tail -n 1
   [ -f $P/lib/libLLVMSPIRVLib.a ] || { ls $P/lib; echo "no libLLVMSPIRVLib.a"; exit 1; }
   v=$(pkg-config --modversion LLVMSPIRVLib)
   case "$v" in 23.1.*) echo "pkg-config LLVMSPIRVLib $v" ;; *) echo "LLVMSPIRVLib reports version '$v' (Mesa wants 23.1.x)"; exit 1 ;; esac
   ;;
glslang)
   # glslang (Vulkan SDK 1.4.363): Mesa's Vulkan drivers (anv, radv) compile internal GLSL shaders with
   # glslangValidator while they are built. Against SPIRV-Tools of the same SDK. Build root only.
   . $SPIN/stage2-lib.sh
   stage2_check
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   V=1.4.363.0 P=/Programs/Glslang/1.4.363.0 PY=/Programs/Python/3.13.18/bin/python3.13
   unpack glslang-vulkan-sdk-$V.tar.gz glslang-vulkan-sdk-$V
   rm -rf $P
   s2run /Data/Build/glslang-cmake.log cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$P \
      -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH=/Programs/SPIRV-Tools/$V -DBUILD_EXTERNAL=OFF -DALLOW_EXTERNAL_SPIRV_TOOLS=ON \
      -DENABLE_OPT=ON -DGLSLANG_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DPython3_EXECUTABLE=$PY
   s2run /Data/Build/glslang-build.log cmake --build build -j$(nproc)
   s2run /Data/Build/glslang-install.log cmake --install build
   mkdir -p $P/doc && install -m 644 LICENSE.txt $P/doc/
   stage2_resources Glslang $V "GLSL/HLSL to SPIR-V compiler glslangValidator (Khronos, Vulkan SDK $V; build root only)" \
      "BSD-3-Clause AND others (see doc/LICENSE.txt)" https://github.com/KhronosGroup/glslang \
      https://github.com/KhronosGroup/glslang/archive/refs/tags/vulkan-sdk-$V.tar.gz SPIRV-Tools
   # 017.01 has glslang 8.13 as the program "GSLLang" (sic): its index links make room in this root
   stage2_unlink /Programs/GSLLang/
   ln -sfn $V /Programs/Glslang/Current
   SymlinkProgram Glslang $V | tail -n 1
   glslangValidator --version | head -n 1
   printf '#version 450\nlayout(local_size_x = 8) in;\nlayout(binding = 0) buffer B { uint v[]; };\nvoid main() { v[gl_GlobalInvocationID.x] *= 2u; }\n' > $WORK/t.comp
   glslangValidator -V --target-env vulkan1.2 -o $WORK/t.spv $WORK/t.comp > /dev/null && spirv-val --target-env vulkan1.2 $WORK/t.spv &&
      echo "glslang: test compute shader compiled and validated" || { echo "glslang test shader failed"; exit 1; }
   ;;
vulkan)
   # The Vulkan loader (libvulkan.so.1) and vulkaninfo, with the headers they are built from (all of the
   # Vulkan SDK 1.4.363). 017.01 has Mesa's Intel/AMD Vulkan drivers but no loader. X11 only (no
   # Wayland in 017.01). Loader and vulkaninfo go into the image; the headers stay in the build root.
   . $SPIN/stage2-lib.sh
   stage2_check
   export LDFLAGS="-fuse-ld=bfd"   # not 017.01's default ld (gold): see the note above pymods
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   S=vulkan-sdk-1.4.363.0 V=1.4.363 PH=/Programs/Vulkan-Headers/1.4.363 PL=/Programs/Vulkan-Loader/1.4.363 PT=/Programs/Vulkan-Tools/1.4.363
   U=https://github.com/KhronosGroup
   unpack Vulkan-Headers-$S.tar.gz Vulkan-Headers-$S
   rm -rf $PH
   s2run /Data/Build/vulkan-headers-cmake.log cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=$PH -DCMAKE_INSTALL_LIBDIR=lib
   s2run /Data/Build/vulkan-headers-install.log sh -c 'cmake --build build && cmake --install build'
   mkdir -p $PH/doc && install -m 644 LICENSE.md $PH/doc/
   stage2_resources Vulkan-Headers $V "Vulkan headers and registry (Khronos; build root only)" "Apache-2.0 OR MIT" \
      $U/Vulkan-Headers $U/Vulkan-Headers/archive/refs/tags/$S.tar.gz
   ln -sfn $V /Programs/Vulkan-Headers/Current
   SymlinkProgram Vulkan-Headers $V | tail -n 1
   unpack Vulkan-Loader-$S.tar.gz Vulkan-Loader-$S
   rm -rf $PL
   s2run /Data/Build/vulkan-loader-cmake.log cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PL \
      -DCMAKE_INSTALL_LIBDIR=lib -DVulkanHeaders_DIR=$PH/share/cmake/VulkanHeaders -DSYSCONFDIR=/etc \
      -DBUILD_WSI_WAYLAND_SUPPORT=OFF -DBUILD_WSI_XCB_SUPPORT=ON -DBUILD_WSI_XLIB_SUPPORT=ON -DBUILD_TESTS=OFF
   s2run /Data/Build/vulkan-loader-build.log cmake --build build -j$(nproc)
   s2run /Data/Build/vulkan-loader-install.log cmake --install build
   mkdir -p $PL/doc && install -m 644 LICENSE.txt $PL/doc/
   stage2_resources Vulkan-Loader $V "Vulkan loader libvulkan.so.1 (Khronos, Vulkan SDK $V)" "Apache-2.0" \
      $U/Vulkan-Loader $U/Vulkan-Loader/archive/refs/tags/$S.tar.gz LibX11 LibXCB LibXrandr
   echo "built in the stage-2 build root (glibc 2.38) of GoboRefined's build/build.sh; in the image (0.10.4)" > $PL/Resources/GoboRefinedStage
   ln -sfn $V /Programs/Vulkan-Loader/Current
   SymlinkProgram Vulkan-Loader $V | tail -n 1
   [ -e $PL/lib/libvulkan.so.1 ] || { ls $PL/lib; echo "no libvulkan.so.1"; exit 1; }
   unpack Vulkan-Tools-$S.tar.gz Vulkan-Tools-$S
   rm -rf $PT
   s2run /Data/Build/vulkan-tools-cmake.log cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$PT \
      -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$PH;$PL" -DVulkanHeaders_DIR=$PH/share/cmake/VulkanHeaders \
      -DBUILD_CUBE=OFF -DBUILD_ICD=OFF -DBUILD_TESTS=OFF -DBUILD_VULKANINFO=ON -DBUILD_WSI_WAYLAND_SUPPORT=OFF \
      -DBUILD_WSI_XCB_SUPPORT=ON -DBUILD_WSI_XLIB_SUPPORT=ON
   s2run /Data/Build/vulkan-tools-build.log cmake --build build -j$(nproc)
   s2run /Data/Build/vulkan-tools-install.log cmake --install build
   mkdir -p $PT/doc && install -m 644 LICENSE.txt $PT/doc/
   stage2_resources Vulkan-Tools $V "vulkaninfo: Vulkan devices and drivers (Khronos, Vulkan SDK $V)" "Apache-2.0" \
      $U/Vulkan-Tools $U/Vulkan-Tools/archive/refs/tags/$S.tar.gz Vulkan-Loader
   echo "built in the stage-2 build root (glibc 2.38) of GoboRefined's build/build.sh; in the image (0.10.4)" > $PT/Resources/GoboRefinedStage
   ln -sfn $V /Programs/Vulkan-Tools/Current
   SymlinkProgram Vulkan-Tools $V | tail -n 1
   [ -x $PT/bin/vulkaninfo ] || { ls $PT/bin; echo "no vulkaninfo"; exit 1; }
   # vulkaninfo loads libvulkan.so.1 at run time (dlopen), it does not link it
   ! ldd $PT/bin/vulkaninfo | grep -q 'not found' || { ldd $PT/bin/vulkaninfo; echo "vulkaninfo misses libraries"; exit 1; }
   strings $PT/bin/vulkaninfo | grep -qx 'libvulkan.so.1' || { echo "vulkaninfo does not name libvulkan.so.1"; exit 1; }
   case "$(readlink -f /System/Index/lib/libvulkan.so.1)" in $PL/lib/*) ;; *) echo "libvulkan.so.1 is not the new loader's"; exit 1 ;; esac
   ;;
libdrm)
   # libdrm 2.4.134 (017.01: 2.4.100; Mesa 26 needs >= 2.4.133 for radeonsi/radv). Same sonames
   # (libdrm.so.2, _amdgpu.so.1, _intel.so.1, _nouveau.so.2, _radeon.so.1); 2.4.100's libkms.so.1 is
   # gone upstream (nothing in 017.01 links it). Goes into the image in place of 2.4.100.
   . $SPIN/stage2-lib.sh
   stage2_check
   export LDFLAGS="-fuse-ld=bfd"   # not 017.01's default ld (gold): see the note above pymods
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   V=2.4.134 P=/Programs/LibDRM/2.4.134
   unpack libdrm-$V.tar.xz libdrm-$V
   rm -rf $P
   s2run /Data/Build/libdrm-meson.log meson setup build --prefix=$P --libdir=lib --buildtype=release \
      -Dintel=enabled -Dradeon=enabled -Damdgpu=enabled -Dnouveau=enabled -Dvmwgfx=enabled \
      -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled \
      -Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false -Dudev=false -Dinstall-test-programs=false
   s2run /Data/Build/libdrm-build.log ninja -C build
   s2run /Data/Build/libdrm-install.log ninja -C build install
   mkdir -p $P/doc && sed -n '1,/\*\//p' xf86drm.c > $P/doc/COPYING
   stage2_resources LibDRM $V "Userspace interface to the kernel's direct rendering manager (DRM)" "MIT" \
      https://dri.freedesktop.org/ https://dri.freedesktop.org/libdrm/libdrm-$V.tar.xz LibPCIAccess
   echo "built in the stage-2 build root (glibc 2.38) of GoboRefined's build/build.sh; in the image (0.10.4)" > $P/Resources/GoboRefinedStage
   stage2_unlink /Programs/LibDRM/2.4.100/
   ln -sfn $V /Programs/LibDRM/Current
   SymlinkProgram LibDRM $V | tail -n 1
   for l in libdrm.so.2 libdrm_amdgpu.so.1 libdrm_intel.so.1 libdrm_nouveau.so.2 libdrm_radeon.so.1
   do
      case "$(readlink -f /System/Index/lib/$l)" in $P/lib/*) ;; *) echo "$l is not LibDRM $V's"; exit 1 ;; esac
   done
   [ "$(pkg-config --modversion libdrm)" = $V ] || { echo "pkg-config libdrm is not $V"; exit 1; }
   ;;
libglvnd)
   # libglvnd 1.7.0 (017.01: 1.2.0; Mesa 26 needs >= 1.3.2): libGL, libEGL, libGLX, libGLES*, libOpenGL
   # dispatch to the vendor library (Mesa). Same sonames. The EGL vendor folders are the ones 017.01's
   # build uses (/System/Settings/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d); libglvnd installs
   # nothing into them. Goes into the image in place of 1.2.0.
   . $SPIN/stage2-lib.sh
   stage2_check
   export LDFLAGS="-fuse-ld=bfd"   # not 017.01's default ld (gold): see the note above pymods
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   V=1.7.0 P=/Programs/LibGLVnd/1.7.0
   unpack libglvnd-v$V.tar.gz libglvnd-v$V
   rm -rf $P
   touch $WORK/libglvnd-stamp
   s2run /Data/Build/libglvnd-meson.log meson setup build --prefix=$P --libdir=lib --buildtype=release \
      --sysconfdir=/System/Settings --datadir=/usr/share -Dx11=enabled -Dglx=enabled -Degl=true -Dgles1=true -Dgles2=true -Dheaders=true
   s2run /Data/Build/libglvnd-build.log ninja -C build
   s2run /Data/Build/libglvnd-install.log ninja -C build install
   [ -z "$(find /System/Settings/glvnd /System/Index/share/glvnd -newer $WORK/libglvnd-stamp 2> /dev/null)" ] ||
      { echo "libglvnd installed files outside its program folder"; exit 1; }
   mkdir -p $P/doc && install -m 644 README.md $P/doc/
   stage2_resources LibGLVnd $V "GL Vendor-Neutral Dispatch library (libGL, libEGL, libGLX, libGLES, libOpenGL)" "MIT" \
      https://gitlab.freedesktop.org/glvnd/libglvnd https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v$V/libglvnd-v$V.tar.gz LibX11 LibXext
   echo "built in the stage-2 build root (glibc 2.38) of GoboRefined's build/build.sh; in the image (0.10.4)" > $P/Resources/GoboRefinedStage
   stage2_unlink /Programs/LibGLVnd/1.2.0/
   ln -sfn $V /Programs/LibGLVnd/Current
   SymlinkProgram LibGLVnd $V | tail -n 1
   for l in libGL.so.1 libEGL.so.1 libGLX.so.0 libGLdispatch.so.0 libOpenGL.so.0 libGLESv2.so.2 libGLESv1_CM.so.1
   do
      case "$(readlink -f /System/Index/lib/$l)" in $P/lib/*) ;; *) echo "$l is not LibGLVnd $V's"; exit 1 ;; esac
   done
   strings $P/lib/libEGL.so.1 | grep -qx '/System/Settings/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d' ||
      { strings $P/lib/libEGL.so.1 | grep egl_vendor; echo "libEGL looks for EGL vendors elsewhere"; exit 1; }
   ;;
mesa)
   # Mesa 26.3.1 (017.01: 19.3.3), X11 only: Gallium nouveau (NVIDIA), iris + crocus (Intel), radeonsi +
   # r600 (AMD), svga (VirtualBox/VMware), zink (GL on Vulkan), llvmpipe + softpipe (software); Vulkan
   # anv (Intel), radv (AMD), lavapipe (software); VA-API for nouveau/radeonsi/r600 (free codecs only:
   # Mesa's default "all_free"). No NVK (needs Rust >= 1.85). LLVM 23.1.6 is static (llvm.org's build):
   # linked into Mesa's libraries (libgallium, libvulkan_*), nothing named libLLVM goes into the image.
   # GLX on X11 is DRI3-only since Mesa 25; for Xorg 1.20's AIGLX Mesa still builds the "dril" loader
   # stubs (lib/dri/<name>_dri.so). No libxatracker any more (Xorg's vmware DDX needs it): VirtualBox
   # and VMware go to the modesetting driver (spin/ab/20-gobo-modesetting.conf).
   . $SPIN/stage2-lib.sh
   stage2_check
   export LDFLAGS="-fuse-ld=bfd"   # not 017.01's default ld (gold): see the note above pymods
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   V=26.3.1 P=/Programs/Mesa/26.3.1
   [ "$(readlink /Programs/LibDRM/Current)" = 2.4.134 ] && [ "$(readlink /Programs/LibGLVnd/Current)" = 1.7.0 ] ||
      { echo "LibDRM 2.4.134 / LibGLVnd 1.7.0 are not built (steps libdrm, libglvnd)"; exit 1; }
   command -v glslangValidator > /dev/null && pkg-config --exists LLVMSPIRVLib SPIRV-Tools ||
      { echo "glslang / SPIRV-LLVM-Translator / SPIRV-Tools missing (steps glslang, spirv-translator, spirv-tools)"; exit 1; }
   unpack mesa-$V.tar.xz mesa-$V
   rm -rf $P
   # the llvm.org LLVM is built without RTTI: Mesa's C++ must be too (cpp_rtti=false)
   [ "$(llvm-config --has-rtti)" = NO ] || { echo "LLVM has RTTI now: drop -Dcpp_rtti=false"; exit 1; }
   # TLS: Mesa picks -mtls-dialect=gnu2 when the toolchain runs it, but gold (017.01's default ld) then
   # failed on gcc 14's code ("TLS relocation against invalid instruction"). Kept on the classic dialect
   # with ld.bfd too (proven in the VM; gnu2 is only a speed-up)
   s2run /Data/Build/mesa-meson.log meson setup build --prefix=$P --libdir=lib --sysconfdir=/etc --buildtype=release \
      -Db_ndebug=true -Dbackend_max_links=2 -Dcpp_rtti=false -Dc_args=-mtls-dialect=gnu -Dcpp_args=-mtls-dialect=gnu \
      -Dplatforms=x11 -Dglx=dri -Degl=enabled -Dgbm=enabled -Dglvnd=enabled -Dopengl=true -Dgles1=enabled -Dgles2=enabled \
      -Dgallium-drivers=nouveau,iris,crocus,radeonsi,r600,llvmpipe,softpipe,svga,zink \
      -Dvulkan-drivers=intel,amd,swrast -Dvulkan-layers=[] -Dtools=[] \
      -Dgallium-va=enabled -Dvideo-codecs=all_free -Dgallium-rusticl=false -Dmicrosoft-clc=disabled \
      -Dllvm=enabled -Dshared-llvm=disabled -Dzstd=enabled -Dexpat=enabled -Dxmlconfig=enabled \
      -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dbuild-tests=false -Dhtml-docs=disabled
   sed -n '/^Message: Configuration summary\|^mesa [0-9]/,$p' /Data/Build/mesa-meson.log | grep -v '^ *$' | head -n 80
   t0=$(date +%s)
   s2run /Data/Build/mesa-build.log ninja -C build
   echo "mesa: compiled in $(( $(date +%s) - t0 )) s"
   s2run /Data/Build/mesa-install.log ninja -C build install
   mkdir -p $P/doc && install -m 644 docs/license.rst $P/doc/
   stage2_resources Mesa $V "OpenGL, EGL, GBM, Vulkan and VA-API drivers (Gallium, Intel/AMD/software Vulkan)" "MIT AND others (see doc/license.rst)" \
      https://www.mesa3d.org/ https://archive.mesa3d.org/mesa-$V.tar.xz LibDRM LibGLVnd LibVA Expat ZLib Zstd ELFUtils LibXML2 LibXshmfence
   echo "built in the stage-2 build root (glibc 2.38) of GoboRefined's build/build.sh; in the image (0.10.4)" > $P/Resources/GoboRefinedStage
   stage2_unlink /Programs/Mesa/19.3.3/
   ln -sfn $V /Programs/Mesa/Current
   SymlinkProgram Mesa $V | tail -n 1
   # checks: the drivers named above, nothing of LLVM/clang/SPIRV needed at run time
   for f in lib/libGLX_mesa.so.0 lib/libEGL_mesa.so.0 lib/libgbm.so.1 lib/libvulkan_intel.so lib/libvulkan_radeon.so lib/libvulkan_lvp.so \
            lib/dri/nouveau_dri.so lib/dri/iris_dri.so lib/dri/crocus_dri.so lib/dri/radeonsi_dri.so lib/dri/r600_dri.so \
            lib/dri/swrast_dri.so lib/dri/kms_swrast_dri.so lib/dri/vmwgfx_dri.so lib/dri/zink_dri.so \
            lib/dri/nouveau_drv_video.so lib/dri/radeonsi_drv_video.so lib/dri/r600_drv_video.so \
            share/vulkan/icd.d/intel_icd.x86_64.json share/vulkan/icd.d/radeon_icd.x86_64.json share/vulkan/icd.d/lvp_icd.x86_64.json
   do [ -e $P/$f ] || { echo "Mesa $V: $f missing"; ls $P/lib $P/lib/dri; exit 1; }
   done
   for f in $(find $P/lib -name '*.so*' -type f)
   do
      ! ldd "$f" | grep -q 'not found' || { ldd "$f" | grep 'not found'; echo "$f misses libraries"; exit 1; }
      ! readelf -d "$f" | grep -E 'NEEDED.*(libLLVM|libclang|libSPIRV|libLTO)' || { echo "$f needs a build-root library"; exit 1; }
   done
   # the Vulkan drivers load and answer (no display needed): lavapipe lists its device; anv/radv find no
   # GPU in the build root and must say so, not crash (the gold link of 0.10.4's first build crashed)
   VK_DRIVER_FILES=$P/share/vulkan/icd.d/lvp_icd.x86_64.json vulkaninfo --summary > /Data/Build/mesa-vk-lvp.log 2>&1 &&
      grep -q 'llvmpipe' /Data/Build/mesa-vk-lvp.log || { tail -n 20 /Data/Build/mesa-vk-lvp.log; echo "vulkaninfo with lavapipe failed"; exit 1; }
   grep -m 1 'deviceName' /Data/Build/mesa-vk-lvp.log
   for d in intel radeon
   do
      rc=0; VK_DRIVER_FILES=$P/share/vulkan/icd.d/${d}_icd.x86_64.json vulkaninfo --summary > /Data/Build/mesa-vk-$d.log 2>&1 || rc=$?
      [ $rc -lt 128 ] || { tail -n 20 /Data/Build/mesa-vk-$d.log; echo "vulkaninfo with the $d driver crashed (exit $rc)"; exit 1; }
      echo "vulkaninfo with the $d driver and no such GPU: exit $rc (no crash)"
   done
   echo "libgallium needs: $(readelf -d $P/lib/libgallium-$V.so | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | tr '\n' ' ')"
   du -sh $P $P/lib/libgallium-$V.so $P/lib/libvulkan_*.so
   ;;
mesa-demos)
   # glxinfo, eglinfo and glxgears from mesa-demos 9.0.0 (017.01 has none of them): "glxinfo -B" shows
   # the OpenGL driver in use. Only these three programs are installed. Goes into the image.
   . $SPIN/stage2-lib.sh
   stage2_check
   export LDFLAGS="-fuse-ld=bfd"   # not 017.01's default ld (gold): see the note above pymods
   s2run() { local log=$1; shift; "$@" > "$log" 2>&1 || { grep -m 10 -B 2 -A 4 -E 'error|Error|ERROR' "$log" | head -n 60; tail -n 30 "$log"; exit 1; }; }
   V=9.0.0 P=/Programs/Mesa-Demos/9.0.0
   [ "$(readlink /Programs/Mesa/Current)" = 26.3.1 ] || { echo "Mesa 26.3.1 is not built (step mesa)"; exit 1; }
   unpack mesa-demos-$V.tar.xz mesa-demos-$V
   rm -rf $P
   s2run /Data/Build/mesa-demos-meson.log meson setup build --prefix=$P --buildtype=release \
      -Degl=enabled -Dx11=enabled -Dgles1=disabled -Dgles2=disabled -Dglut=disabled -Dosmesa=disabled \
      -Dlibdrm=enabled -Dvulkan=disabled -Dwayland=disabled
   s2run /Data/Build/mesa-demos-build.log ninja -C build src/xdemos/glxinfo src/xdemos/glxgears src/egl/opengl/eglinfo
   mkdir -p $P/bin $P/doc
   install -m 755 build/src/xdemos/glxinfo build/src/xdemos/glxgears build/src/egl/opengl/eglinfo $P/bin/
   sed -n '1,/\*\//p' src/xdemos/glxinfo.c > $P/doc/COPYING
   stage2_resources Mesa-Demos $V "glxinfo, eglinfo, glxgears (OpenGL information and test)" "MIT" \
      https://gitlab.freedesktop.org/mesa/demos https://archive.mesa3d.org/demos/mesa-demos-$V.tar.xz LibGLVnd LibX11
   echo "built in the stage-2 build root (glibc 2.38) of GoboRefined's build/build.sh; in the image (0.10.4)" > $P/Resources/GoboRefinedStage
   ln -sfn $V /Programs/Mesa-Demos/Current
   SymlinkProgram Mesa-Demos $V | tail -n 1
   for b in glxinfo eglinfo glxgears
   do ! ldd $P/bin/$b | grep -q 'not found' || { ldd $P/bin/$b; echo "$b misses libraries"; exit 1; }
   done
   ;;
*) echo "unknown step: $1"; exit 1 ;;
esac
echo "STEP-DONE $1"
