#!/bin/bash
# Rebuild the GoboRefined ISO (unofficial spin of GoboLinux 017.01).
# Runs INSIDE the build VM (snapshot "iso-build-env-5"), as root:
#
#   wget -qO /Data/Build/build-iso.sh http://10.0.2.2:8766/build-iso.sh && bash /Data/Build/build-iso.sh
#
# Needs, in the VM:
#   - the stock GoboLinux-017.01 ISO attached as /dev/sr0
#   - /Data/Build/rootfs            unpacked stock gobolinux-live.squashfs (unsquashfs)
#   - /Data/Build/xorriso-inst      GNU xorriso built from source
#   - /Programs/XRandR-Tool         xrandr built from source
#   - /Programs/Inter, /Programs/JetBrains-Mono, /Programs/Papirus-Icon-Theme
#                                   fonts and icons (snapshot "iso-build-env-3"; tarballs in spin/programs/)
#   - /Programs/Menu-Cache, LibFM, PCManFM, PaVuControl, LxRandr, LXDM
#                                   desktop programs (snapshot "iso-build-env-4"; built with
#                                   spin/build-programs.sh; tarballs in spin/programs/)
#   - /Programs/Udevil, USB-ModeSwitch, RTL8852AU, OnlyOffice
#                                   USB automount, Wi-Fi mode switch + driver, office suite
#                                   (snapshot "iso-build-env-5"; spin/build-programs.sh)
# and on the host: `node vm/serve.js` serving installer/gobo-install, gobo11.tgz, welcome.src,
# gobo-command-not-found and software-install.txt (copies of spin/gobo-command-not-found and
# docs/software-install.md in vm/serve/), lxdm-files.tgz (cd spin && tar czf ../vm/serve/lxdm-files.tgz
# --exclude=render-title.sh lxdm).
set -e
B=/Data/Build
R=$B/rootfs
HOST=http://10.0.2.2:8766
VERSION=0.5
# GoboRefined = the spin's name (unofficial, based on GoboLinux 017.01). The volume label below must
# stay GOBOLINUX_LIVE_INSTALLER: the live boot looks for the medium by it.
OUT=$B/GoboRefined-$VERSION.iso
cd $B

echo "== fetching installer and look from the host"
for f in gobo-install gobo11.tgz welcome.src gobo-command-not-found software-install.txt
do wget -qO $f $HOST/$f
done
bash -n gobo-install
rm -rf gobo11 && tar xzf gobo11.tgz 2>/dev/null

echo "== adding programs to the live image"
EXTRA="XRandR-Tool Inter JetBrains-Mono Papirus-Icon-Theme Menu-Cache LibFM PCManFM PaVuControl LxRandr LXDM
       Udevil USB-ModeSwitch OnlyOffice"
# kernel modules are not linked by SymlinkProgram (/System/Index/lib/modules is a link into Linux)
MODULES="RTL8852AU"
KREL=6.12.16-Gobo
for prog in $EXTRA $MODULES
do rm -rf $R/Programs/$prog && cp -a /Programs/$prog $R/Programs/
done
# Login screen theme files (title image "GoboRefined", wallpaper, CSS) from spin/lxdm on the host,
# so a theme change does not depend on the build VM's copy of /Programs/LXDM being up to date.
rm -rf lxdm-files && mkdir lxdm-files && wget -qO- $HOST/lxdm-files.tgz | tar xz -C lxdm-files
install -m 644 lxdm-files/lxdm/Gobo11/* $R/Programs/LXDM/0.5.3/share/lxdm/themes/Gobo11/
P=$R/Programs/GoboSpin
rm -rf $P && mkdir -p $P/1.0/bin $P/1.0/share $P/1.0/Resources
install -m 755 gobo-install $P/1.0/bin/gobo-install
install -m 755 gobo-command-not-found $P/1.0/bin/gobo-command-not-found
mkdir -p $P/1.0/share/doc
install -m 644 software-install.txt $P/1.0/share/doc/software-install.txt
cp -r gobo11 $P/1.0/share/gobo11
echo "GoboRefined (unofficial spin of GoboLinux 017.01): thin installer and desktop look." > $P/1.0/Resources/Description
echo "$VERSION" > $P/1.0/share/spin-version
ln -sfn 1.0 $P/Current
mount -t proc proc $R/proc
for prog in $EXTRA
do chroot $R SymlinkProgram $prog | tail -n 1
done
chroot $R SymlinkProgram GoboSpin | tail -n 1
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
chroot $R modinfo -F alias 8852au | grep -qi 'v2357p013F' || { echo "8852au not in the module index"; exit 1; }
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
# no stray link inside /Mount/Media (USB drives are mounted there; see gobo-install)
[ -L $R/Mount/Media/Media ] && rm -f $R/Mount/Media/Media
umount $R/proc

echo "== look for the live user and for new users (both are copied from the skeleton)"
for skel in $R/Programs/EnhancedSkel/017.01/Resources/Defaults/Settings/skel $R/Programs/EnhancedSkel/Settings/skel
do [ -d $skel ] && sh gobo11/apply.sh $skel us
done

echo "== welcome text"
printf "$(cat welcome.src)\n" > $R/Programs/LiveCD/017.01/Data/Language/Welcome_en_US

echo "== packing the live image"
rm -f $B/gobolinux-live.squashfs $OUT
mksquashfs $R $B/gobolinux-live.squashfs -comp zstd -b 131072 -noappend -no-progress > $B/mksquashfs.log

echo "== writing the ISO (boot records are replayed from the stock ISO)"
$B/xorriso-inst/bin/xorriso -indev stdio:/dev/sr0 -outdev $OUT \
   -boot_image any replay \
   -rm /gobolinux-live.squashfs -- \
   -map $B/gobolinux-live.squashfs /gobolinux-live.squashfs \
   -volid GOBOLINUX_LIVE_INSTALLER > $B/xorriso.log 2>&1 || { tail -n 20 $B/xorriso.log; exit 1; }

ls -la $OUT
sha256sum $OUT
echo BUILD-DONE
