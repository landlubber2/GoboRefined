#!/bin/bash
# Build the stage 3 desktop programs by hand in the build VM (as root), GoboLinux style:
# each one goes to /Programs/<Name>/<Version> (settings in /Programs/<Name>/Settings) and is
# activated with SymlinkProgram. Sources are expected in /Data/Build/src3 (list in HANDOFF.md, stage 3).
#
#   bash build-programs.sh <step>      steps, in order: menu-cache libfm pcmanfm pavucontrol lxrandr lxdm
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
*) echo "unknown step: $1"; exit 1 ;;
esac
echo "STEP-DONE $1"
