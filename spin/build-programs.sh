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
   KREL=6.12.16-Gobo REV=865ab0f V=20240506 P=/Programs/RTL8852AU/20240506
   FULL=865ab0fa91471d595c283d2f3db323f7f15455f5
   unpack rtl8852au-$FULL.tar.gz rtl8852au-$FULL
   make -j2 -C /lib/modules/$KREL/build M=$PWD KERNELRELEASE=$KREL TopDIR=$PWD CONFIG_RTL8852AU=m modules
   rm -rf $P && mkdir -p $P/lib/modules/$KREL/updates $P/Resources $P/doc
   install -m 644 8852au.ko $P/lib/modules/$KREL/updates/
   cp README.md $P/doc/
   echo "Realtek RTL8852AU/RTL8832AU USB Wi-Fi driver (lwfinger/rtl8852au $REV) for kernel $KREL." > $P/Resources/Description
   ln -sfn $V /Programs/RTL8852AU/Current
   # /System/Index/lib/modules is a link into the Linux program, so SymlinkProgram cannot
   # merge modules: link the .ko into the kernel's "updates" directory instead.
   mkdir -p /Programs/Linux/Current/lib/modules/$KREL/updates
   ln -sfn /Programs/RTL8852AU/Current/lib/modules/$KREL/updates/8852au.ko \
      /Programs/Linux/Current/lib/modules/$KREL/updates/8852au.ko
   depmod -a $KREL
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
*) echo "unknown step: $1"; exit 1 ;;
esac
echo "STEP-DONE $1"
