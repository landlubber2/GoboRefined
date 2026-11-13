#!/bin/bash
# Rebuild the spin ISO. Runs INSIDE the build VM (snapshot "iso-build-env"), as root:
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
# and on the host: `node vm/serve.js` serving installer/gobo-install, gobo11.tgz and welcome.src.
set -e
B=/Data/Build
R=$B/rootfs
HOST=http://10.0.2.2:8766
VERSION=0.3
OUT=$B/GoboLinux-017.01-spin-$VERSION.iso
cd $B

echo "== fetching installer and look from the host"
for f in gobo-install gobo11.tgz welcome.src
do wget -qO $f $HOST/$f
done
bash -n gobo-install
rm -rf gobo11 && tar xzf gobo11.tgz 2>/dev/null

echo "== adding programs to the live image"
EXTRA="XRandR-Tool Inter JetBrains-Mono Papirus-Icon-Theme"
for prog in $EXTRA
do rm -rf $R/Programs/$prog && cp -a /Programs/$prog $R/Programs/
done
P=$R/Programs/GoboSpin
rm -rf $P && mkdir -p $P/1.0/bin $P/1.0/share $P/1.0/Resources
install -m 755 gobo-install $P/1.0/bin/gobo-install
cp -r gobo11 $P/1.0/share/gobo11
echo "Thin installer and desktop look of the modernized GoboLinux spin." > $P/1.0/Resources/Description
echo "$VERSION" > $P/1.0/share/spin-version
ln -sfn 1.0 $P/Current
mount -t proc proc $R/proc
for prog in $EXTRA
do chroot $R SymlinkProgram $prog | tail -n 1
done
chroot $R SymlinkProgram GoboSpin | tail -n 1
echo "== refreshing the font cache and the icon caches"
chroot $R fc-cache -f > /dev/null
for t in Papirus Papirus-Dark Papirus-Light
do chroot $R gtk-update-icon-cache -q -f /System/Index/share/icons/$t
done
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
