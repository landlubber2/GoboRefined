# Bug report: GoboLinux 017.01 install hang + recovery notes

**Date:** 2026-11-11 → 2026-11-12  
**Environment:** Windows host, Oracle VirtualBox 7.2.22, VM `GoboLinux-017.01`  
**Guest:** GoboLinux 017.01 x86_64 LiveCD → install to virtual disk  
**VM firmware:** BIOS (not EFI)  
**Disk:** 40 GiB VDI, partition table **msdos** (MBR), single root on `/dev/sda1` (ext4)  
**Reporter context:** Lab/revamp workspace; goal later is easier install / modernization — **not** a full ISO redesign first.

---

## Summary

Official `Installer` copies the system and runs `grub-install` successfully, then **hangs indefinitely** on generating the GRUB config (`GenGrubConf` → `grub-mkconfig`). Upstream wiki documents a pre-install GRUB 2.12-r1 package update; applying it did **not** prevent the hang in this VM. Manual minimal `grub.cfg` unblocked boot. Installed system came up on **TTY (Console)**; GUI requires `startx` / Graphic boot script.

---

## Severity

**High** for VM/BIOS installs: install appears stuck forever at the last step; naive reboot without a valid `grub.cfg` risks unbootable disk. Workarounds exist but are undocumented in the Installer UI and painful without host↔guest clipboard.

---

## Steps to reproduce

1. Create VirtualBox VM: Linux_64, BIOS, 4 GB RAM, NAT, empty disk + 017.01 ISO attached.
2. Boot LiveCD, start desktop, partition disk with **msdos** (per upstream: GPT/UEFI in VMs is flaky).
3. (Optional) Per [Known Issues](https://www.wiki.gobolinux.org/Quick-Start/GoboLinux-Known-Issues-and-Fixes/index.html):

   ```fish
   InstallPackage https://gobonextgen.org/Packages/017.01/GRUB--2.12-r1--x86_64.tar.bz2
   InstallPackage https://gobonextgen.org/Packages/017.01/GRUB-EFI--2.12-r1--x86_64.tar.bz2
   ```

   Choose **U** on settings prompts. `SymlinkProgram` may print many **Conflict** lines for shared GRUB/GRUB-EFI files; packages can still finish with `Done.`
4. Run `Installer`, install to `/dev/sda1`, enable bootloader to MBR of `sda`.
5. Observe progress log through GRUB install, then stall.

---

## Actual result

Installer log ends around:

```text
==> Creating GRUB config file
==> Installing GRUB
Installing for i386-pc platform.
Installation finished. No error reported.
Generating grub configuration file...
```

- Progress dialog **Ok** stays disabled for **>1 hour**.
- Manual retry from LiveCD after abort:

  ```fish
  chroot /Mount/GoboLinux env GRUB_DISABLE_OS_PROBER=true GenGrubConf /boot/grub
  ```

  still hangs; Ctrl+C shows Python `KeyboardInterrupt` waiting on `subprocess` / `grub-mkconfig` inside `GenGrubConf`.

---

## Expected result

- GRUB config generation finishes in a short time, or
- Installer detects stall / failure and offers a fallback (e.g. write a minimal `grub.cfg`), and
- Clear LiveCD messaging if GRUB r1 must be installed first.

---

## Root cause (likely)

`Installer` → `BootLoader.createGrubConfig()` → `chroot … GenGrubConf /boot/grub`  
`GenGrubConf` (`ConfigTools`) calls `grub-mkconfig`. In this Live+chroot+VM setup `grub-mkconfig` does not return (typical suspects: device probing / os-prober / Gobo device paths). Hang is **after** successful `grub-install`.

Relevant pieces:

| Piece | Role |
| --- | --- |
| `gobolinux/Installer` | Orchestrates copy + `grub-install` + `GenGrubConf` |
| `gobolinux/ConfigTools` → `GenGrubConf` | Wraps `grub-mkconfig`, rewrites paths/PARTUUID |
| GRUB 2.12 (+ wiki r1 packages) | Bootloader; r1 alone did not fix hang here |
| LiveCD / BuildLiveCD | What ships on the ISO |

---

## Disk / boot facts from this install (after hang)

```text
/dev/sda1: UUID="fb229e0f-2364-4063-b721-1eb3ed800f57" TYPE="ext4" PARTUUID="810c49c5-01"

/Mount/GoboLinux/System/Kernel/Boot/
  kernel -> kernel-6.12.16-Gobo
  kernel-6.12.16-Gobo
  initramfs-6.12.16-Gobo.img
  grub/
```

Working **minimal** `grub.cfg` used for recovery:

```grub
set timeout=5
set default=0

menuentry "GoboLinux 017.01" {
    insmod part_msdos
    insmod ext2
    set root=(hd0,msdos1)
    linux /System/Kernel/Boot/kernel root=PARTUUID=810c49c5-01 vt.default_utf8=1 rootwait net.ifnames=0
    initrd /System/Kernel/Boot/initramfs-6.12.16-Gobo.img
}
EOF
```

(Written under `/System/Kernel/Boot/grub/grub.cfg` on the target.)

Post-recovery: `umount -lR /Mount/GoboLinux`; LiveCD `reboot` hit I/O error — host **Machine → Reset** worked. Detach ISO before reboot so disk boots.

---

## Secondary issues (same session)

1. **Host↔guest clipboard** broken in VirtualBox + Gobo Live (known; spice-vdagent / Guest Additions not out of the box). Workaround: HTTP bridge on host `vm/clipboard-bridge/` → guest `http://10.0.2.2:8765/`.
2. Terminal paste: **Ctrl+V** does not paste; **Ctrl+Shift+V** / Shift+Insert / middle-click; some terminals still awkward under VBox keyboard capture.
3. Scripts served from Windows had **CRLF**; bash saw `$'\r'` in paths. Serve LF-only or `sed -i 's/\r$//'`.
4. After successful disk boot: **TTY login only** (`Welcome to GoboLinux 017.01`, `user1@NewMachine`). GUI exists (Awesome on LiveCD) but installed default felt like **Console** boot — use `startx` or switch boot script to **Graphic**.
5. Install UX does not prominently force GRUB r1 / MBR-for-VM guidance inside the wizard.

---

## Suggested upstream / project fixes (priority)

1. **Installer:** after `grub-install`, do not block forever on `grub-mkconfig`; set `GRUB_DISABLE_OS_PROBER=true`; timeout; on failure write minimal `grub.cfg` (kernel symlink + initramfs + PARTUUID).
2. **LiveCD / docs / Installer splash:** mandatory GRUB 2.12-r1 step or ship r1 on the ISO.
3. **VM docs:** BIOS + msdos; detach ISO; Graphic vs Console / `startx`.
4. **Lab direction (this repo):** prefer **patch or thin lab installer** (simple disk copy + known-good `grub.cfg`) over rewriting the whole distribution ISO.

---

## Status after recovery

- Installed GoboLinux **017.01** boots from VDI (kernel 6.12.16-Gobo).
- Login on tty works (`user1`).
- Desktop not verified as default boot target; `startx` not fully confirmed in this report.
- Stage 2 VM notes: see `vm/README.md`. Clipboard bridge: `vm/clipboard-bridge/`.

---

## References

- https://www.wiki.gobolinux.org/Quick-Start/GoboLinux-Known-Issues-and-Fixes/index.html  
- https://gobolinux.org/release_notes_017.01.html  
- https://github.com/gobolinux/Installer  
- https://github.com/gobolinux/ConfigTools/blob/master/bin/GenGrubConf  
