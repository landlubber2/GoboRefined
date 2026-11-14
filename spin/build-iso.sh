#!/bin/bash
# Rebuild the GoboRefined ISO (unofficial spin of GoboLinux 017.01).
# Runs INSIDE the build VM (snapshot "iso-build-env-8a"), as root:
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
#   - /Programs/CopyQ, and USB-ModeSwitch rebuilt with gobo-wifi-switch + the new udev rule
#                                   clipboard history, Wi-Fi switch wrapper (snapshot "iso-build-env-6a")
#   - LibFM and PCManFM rebuilt with spin/patches/*-gobo.patch (search, USB entry, folder icons,
#     trash rule, desktop menu/work area), /Programs/GoboFiles (Trash window, folder colours)
#                                   (snapshot "iso-build-env-6b"; spin/build-programs.sh)
# and on the host: `node vm/serve.js` serving installer/gobo-install, gobo11.tgz, welcome.src,
# gobo-command-not-found and software-install.txt (copies of spin/gobo-command-not-found and
# docs/software-install.md in vm/serve/), lxdm-files.tgz (cd spin && tar czf ../vm/serve/lxdm-files.tgz
# --exclude=render-title.sh lxdm), ab.tgz (0.8 A/B system: cd spin && tar czf ../vm/serve/ab.tgz ab).
#
# 0.8: also writes GoboRefined-$VERSION.update (the pristine system as a signed squashfs, for
# gobo-update) next to the ISO. The signing key is NOT in the VM: before the build, put it into
# memory only, from the host:  vm/ssh.sh 'umask 077; cat > /dev/shm/gobo-update-signing.pem' \
#                                 < vm/keys/update-signing.pem
# This script deletes it when it ends. Needs about 13 GB free in /Data/Build.
set -e
B=/Data/Build
R=$B/rootfs
HOST=http://10.0.2.2:8766
VERSION=${VERSION:-0.8-dev2}
SIGNING_KEY=${SIGNING_KEY:-/dev/shm/gobo-update-signing.pem}
# GoboRefined = the spin's name (unofficial, based on GoboLinux 017.01). The volume label below must
# stay GOBOLINUX_LIVE_INSTALLER: the live boot looks for the medium by it.
OUT=$B/GoboRefined-$VERSION.iso
UPDATE=$B/GoboRefined-$VERSION.update
cd $B
[[ "$VERSION" =~ ^[0-9A-Za-z.-]+$ ]] || { echo "bad VERSION"; exit 1; }
[ -s "$SIGNING_KEY" ] || { echo "no signing key at $SIGNING_KEY (see the header of this script)"; exit 1; }
trap 'rm -f "$SIGNING_KEY"' EXIT

echo "== fetching installer and look from the host"
for f in gobo-install gobo11.tgz welcome.src gobo-command-not-found software-install.txt ab.tgz
do wget -qO $f $HOST/$f
done
bash -n gobo-install
rm -rf gobo11 && tar xzf gobo11.tgz 2>/dev/null
rm -rf ab && tar xzf ab.tgz 2>/dev/null
bash -n ab/gobo-update && bash -n ab/gobo-make-system && bash -n ab/dracut/90goboab/module-setup.sh
for f in ab/dracut/90goboab/goboab-*.sh; do sh -n $f; done
openssl pkey -in "$SIGNING_KEY" -pubout 2>/dev/null | cmp -s - ab/update-signing.pub.pem ||
   { echo "the signing key does not belong to ab/update-signing.pub.pem"; exit 1; }

echo "== adding programs to the live image"
EXTRA="XRandR-Tool Inter JetBrains-Mono Papirus-Icon-Theme Menu-Cache LibFM PCManFM PaVuControl LxRandr LXDM
       Udevil USB-ModeSwitch OnlyOffice CopyQ GoboFiles"
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
# 0.8 A/B system: update tool, system tree builder (used by gobo-install and below), the
# initramfs module, the update signing key (public), the cache list, the udev rule that keeps
# the GOBO_* partitions away from devmon/udevil.
install -m 755 ab/gobo-update $P/1.0/bin/gobo-update
install -m 755 ab/gobo-make-system $P/1.0/bin/gobo-make-system
mkdir -p $P/1.0/share/gobo-update/dracut $P/1.0/lib/udev/rules.d
cp -r ab/dracut/90goboab $P/1.0/share/gobo-update/dracut/
chmod 755 $P/1.0/share/gobo-update/dracut/90goboab/*.sh
install -m 644 ab/update-signing.pub.pem ab/generated-caches $P/1.0/share/gobo-update/
install -m 644 ab/80-gobo-internal.rules $P/1.0/lib/udev/rules.d/
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
[ -e $R/System/Index/share/file-manager/actions/gobo-folder-colour.desktop ] || { echo "folder colour action not linked"; exit 1; }
# no stray link inside /Mount/Media (USB drives are mounted there; see gobo-install)
[ -L $R/Mount/Media/Media ] && rm -f $R/Mount/Media/Media
echo "== initramfs with the A/B root (dracut module goboab; same modules as the stock image + goboab)"
DRACUT_MODS=$R/Programs/Dracut/Current/lib/dracut/modules.d
ln -sfn /Programs/GoboSpin/Current/share/gobo-update/dracut/90goboab $DRACUT_MODS/90goboab
mount --rbind /sys $R/System/Kernel/Objects
mount --rbind /dev $R/System/Kernel/Devices
IMG=/Programs/Linux/Current/Resources/Unmanaged/System/Kernel/Boot/initramfs-$KREL.img
chroot $R dracut --kver $KREL --force --no-hostonly -L 4 --add goboab $IMG > $B/dracut.log 2>&1 ||
   { tail -n 20 $B/dracut.log; exit 1; }
umount -R $R/System/Kernel/Devices; umount -R $R/System/Kernel/Objects
cp $R$IMG $R/System/Kernel/Boot/initramfs-$KREL.img
chroot $R lsinitrd $IMG > $B/lsinitrd.log
grep -q 'bin/goboab-root' $B/lsinitrd.log && grep -q 'overlay.ko' $B/lsinitrd.log ||
   { echo "goboab missing from the initramfs"; exit 1; }
umount $R/proc

echo "== look for the live user and for new users (both are copied from the skeleton)"
for skel in $R/Programs/EnhancedSkel/017.01/Resources/Defaults/Settings/skel $R/Programs/EnhancedSkel/Settings/skel
do [ -d $skel ] && sh gobo11/apply.sh $skel us
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
   echo "GOBOREFINED-UPDATE 1"
   echo "name=GoboRefined"
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
$B/xorriso-inst/bin/xorriso -indev stdio:/dev/sr0 -outdev $OUT \
   -boot_image any replay \
   -rm /gobolinux-live.squashfs -- \
   -map $B/gobolinux-live.squashfs /gobolinux-live.squashfs \
   -volid GOBOLINUX_LIVE_INSTALLER > $B/xorriso.log 2>&1 || { tail -n 20 $B/xorriso.log; exit 1; }

ls -la $OUT
sha256sum $OUT
echo BUILD-DONE
