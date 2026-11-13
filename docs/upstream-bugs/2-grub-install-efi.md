# `grub-install --target=x86_64-efi` in the target chroot produces a loader that cannot read the disk

**Version:** GoboLinux 017.01 x86_64, GRUB 2.12, VirtualBox 7.2.22 with EFI firmware, GPT disk
(ESP `sda1` FAT32, root `sda2` ext4).

## Steps

With the target mounted at `/Mount/GoboLinux`, proc/sys/dev rbind-mounted, and the ESP mounted at
`/Mount/GoboLinux/System/Kernel/ESP`, run what the Installer runs:

```sh
chroot /Mount/GoboLinux grub-install --target=x86_64-efi --no-floppy --removable \
   --efi-directory=/System/Kernel/ESP --boot-directory=/System/Kernel/ESP --bootloader-id=GRUB
```

It prints "Installation finished. No error reported."

## Result

On boot: `error: unknown filesystem. Entering rescue mode...` and a `grub rescue>` prompt.
Adding `part_gpt fat ext2 normal ...` with `--modules` gets as far as a bare `grub>` prompt: the loader
runs but its prefix does not point at the GRUB directory, so no menu is loaded.

## Cause (as far as investigated)

Inside the chroot:

```text
grub-probe -t device  /System/Kernel/ESP   ->  /System/Kernel/Devices/sda1
grub-probe -t partmap /System/Kernel/ESP   ->  (empty)
grub-probe -t fs      /System/Kernel/ESP   ->  fat
```

The device is reported under `/System/Kernel/Devices` and no partition map is found for it, so `grub-install`
embeds neither `part_gpt` nor a usable prefix. This matches the "GPT/UEFI in VMs is flaky" note on the
Known Issues page, and the comment in the Installer source ("Grub cannot handle /S/K/Devices").

## Workaround that boots

Build the image directly, with an embedded script that finds the root filesystem by UUID:

```sh
cat > /tmp/early.cfg <<CFG
search --no-floppy --fs-uuid --set=root <ROOT-FS-UUID>
set prefix=(\$root)/System/Kernel/Boot/grub
configfile \$prefix/grub.cfg
CFG
grub-mkimage -d /Programs/GRUB-EFI/Current/lib/grub/x86_64-efi -O x86_64-efi \
   -o /System/Kernel/ESP/EFI/BOOT/BOOTX64.EFI -c /tmp/early.cfg -p /System/Kernel/Boot/grub \
   part_gpt part_msdos fat ext2 normal configfile search search_fs_uuid linux all_video efi_gop gfxterm font
```

with the `x86_64-efi` modules copied to `/System/Kernel/Boot/grub/x86_64-efi`. Tested in VirtualBox EFI only (a BIOS-or-UEFI real-hardware install also worked,
but which firmware mode that machine used was not recorded).
