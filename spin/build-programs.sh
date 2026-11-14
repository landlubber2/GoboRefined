#!/bin/bash
# Build the stage 3 desktop programs by hand in the build VM (as root), GoboLinux style:
# each one goes to /Programs/<Name>/<Version> (settings in /Programs/<Name>/Settings) and is
# activated with SymlinkProgram. Sources are expected in /Data/Build/src3 (list in HANDOFF.md, stage 3).
#
#   bash build-programs.sh <step>      steps, in order: menu-cache libfm pcmanfm pavucontrol lxrandr lxdm
#                                      0.5: udevil usb-modeswitch rtl8852au onlyoffice
#   (0.5 sources: udevil-0.4.4.tar.gz, usb-modeswitch-2.6.1.tar.bz2 in src3; rtl8852au is cloned
#    from GitHub and onlyoffice downloaded by their steps; list in HANDOFF.md, 0.5 section)
set -e
SRC=/Data/Build/src3
WORK=/Data/Build/work3
mkdir -p $WORK
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

# unpack <tarball>: fresh source tree, cd into it
unpack() {
   local t=$1 d
   d=$(basename $t | sed -E 's/\.tar\.(xz|gz|bz2)$//')
   rm -rf $WORK/$d
   tar xf $SRC/$t -C $WORK
   cd $WORK/$d
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
   gobo_configure LibFM 1.2.5 --with-gtk=3 --disable-exif --disable-actions CFLAGS="$CF"
   # the shortcut editor is not useful as a menu entry
   echo "NoDisplay=true" >> /Programs/LibFM/1.2.5/share/applications/lxshortcut.desktop
   finish LibFM 1.2.5 "File management library used by PCManFM (GTK 3 build)."
   ;;
pcmanfm)
   unpack pcmanfm-1.2.5.tar.xz
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
   # spin's files from spin/lxdm (fetched from the host as lxdm-files.tgz).
   post_install() {
      local S=/Programs/LXDM/Settings
      mkdir -p $S/lxdm $S/pam.d
      mv /etc/lxdm/* $S/lxdm/ && rmdir /etc/lxdm
      rm -f /etc/pam.d/lxdm
      rm -rf /Data/Build/lxdm-files && mkdir -p /Data/Build/lxdm-files
      wget -qO- http://10.0.2.2:8766/lxdm-files.tgz | tar xz -C /Data/Build/lxdm-files
      local F=/Data/Build/lxdm-files/lxdm
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
   # (spin/patches/, served by vm/serve.js like the LXDM files)
   wget -qO- http://10.0.2.2:8766/udevil-0.4.4-gobo-monitor.patch | patch -p1
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
   cat > $P/lib/udev/rules.d/40-gobo-realtek-wifi.rules <<'RULES'
# GoboLinux spin: Realtek Wi-Fi USB adapters (e.g. TP-Link Archer TX20U Plus) first show up
# as a virtual "driver CD" with ID 0bda:1a2b. Eject it, so the adapter re-appears with its
# Wi-Fi ID (e.g. 2357:013f, handled by the 8852au driver), and keep devmon from mounting it.
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="0bda", ATTR{idProduct}=="1a2b", RUN+="/System/Index/bin/usb_modeswitch -K -v 0bda -p 1a2b"
SUBSYSTEM=="block", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="1a2b", ENV{UDISKS_PRESENTATION_NOPOLICY}="1", ENV{UDISKS_IGNORE}="1"
RULES
   echo "Switches USB devices out of their 'driver CD' mode (binary only, spin udev rule for Realtek Wi-Fi)." > $P/Resources/Description
   ln -sfn $V /Programs/USB-ModeSwitch/Current
   SymlinkProgram USB-ModeSwitch $V | tail -n 1
   ;;
rtl8852au)
   # Out-of-tree driver for RTL8852AU/RTL8832AU USB Wi-Fi (TP-Link Archer TX20U Plus 2357:013f/0141);
   # the 6.12 kernel's rtw89 has no USB support. Built against the image's own kernel tree.
   # The kernel tree lacks include/config/kernel.release, so KERNELRELEASE is passed by hand,
   # and the driver's Makefile is used through kbuild directly (it needs TopDIR for that).
   KREL=6.12.16-Gobo REV=865ab0f V=20240506 P=/Programs/RTL8852AU/20240506
   [ -d $SRC/rtl8852au ] || git clone -q https://github.com/lwfinger/rtl8852au.git $SRC/rtl8852au
   rm -rf $WORK/rtl8852au && git clone -q $SRC/rtl8852au $WORK/rtl8852au
   cd $WORK/rtl8852au && git checkout -q $REV
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
   [ -f $SRC/$T ] || wget -q -O $SRC/$T https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v$V/onlyoffice-desktopeditors-x64.tar.xz
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
*) echo "unknown step: $1"; exit 1 ;;
esac
echo "STEP-DONE $1"
