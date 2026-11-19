#!/bin/bash
# GoboRefined A/B root (0.8). Assembles "/" from a read-only system slot (GOBO_A or GOBO_B)
# and the data partition (GOBO_DATA): overlay of slot + install-time settings + later changes,
# /Users and /Data/Variable from the data partition. Only active with root=gobo on the kernel
# command line, so the module is harmless in an image that boots any other way.
# Lives in /Programs/GoboSpin/Current/share/gobo-update/dracut/90goboab; Dracut's modules.d has
# a link to it. Built into the system's initramfs by spin/build-iso.sh (dracut --add goboab).

check() {
    return 255   # only when asked for
}

depends() {
    echo base fs-lib
}

installkernel() {
    hostonly="" instmods overlay ext4 vfat btrfs   # btrfs: the 0.10 layout (prototype)
}

install() {
    inst_hook cmdline 90 "$moddir/goboab-cmdline.sh"
    inst_hook mount 10 "$moddir/goboab-mount.sh"
    inst_script "$moddir/goboab-root.sh" /sbin/goboab-root
    inst_multiple mount umount mkdir rmdir mv rm cp cat sed tr sync chroot fsck.ext4 e2fsck
}
