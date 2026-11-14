# A/B system updates — design for 0.8

Decided 2026-11-14 (owner asked for A/B and said "decide"). This was the brief for the implementation;
it has been corrected where the prototype proved a point wrong (marked **As built**; the reasons are in
HANDOFF.md, section 0.8).

## Goals

- A system update replaces the whole system in one step and can be undone by booting the other slot.
- Nothing the user did is lost by an update: accounts, home folders, settings, programs they added.
- GoboLinux keeps working as GoboLinux: `/Programs/<Name>/<Version>`, `Compile`, `SymlinkProgram`, recipes.
- Reinstalling is the only way from 0.6 to 0.8 (no in-place conversion).

## Facts measured (build VM, 0.6)

Installed system 6.7 GB (6.4 GB of it `/Programs`). Kernel 6.12.16 has overlayfs, squashfs, erofs, loop and
dm-verity as modules. On the image: dracut, grub-editenv, grub-reboot, efibootmgr, mksquashfs, dialog.
Not on the image: sgdisk, rsync.

## Disk layout (whole disk, GPT, at least 32 GB)

| # | Name (GPT and file system label) | Size | Content |
|---|---|---|---|
| 1 | `BIOSBOOT` | 1 MB | BIOS boot partition (GRUB core on BIOS machines) |
| 2 | `GOBO_BOOT` | 512 MB FAT32 | EFI system partition; GRUB, `grub.cfg`, `grubenv` (same partition on BIOS) |
| 3 | `GOBO_A` | 12 GiB ext4 | system slot A, mounted read-only |
| 4 | `GOBO_B` | 12 GiB ext4 | system slot B, mounted read-only |
| 5 | `GOBO_DATA` | rest ext4 | everything that survives updates |

**As built:** "32 GB" is checked as 32,000,000,000 bytes (a disk sold as 32 GB). With two 12 GiB slots the
data partition is then only about 5 GB; it is 8 GB or more from about 35 GB disks on.

No recovery partition: the other slot and the install USB stick are the recovery. Each slot carries its own
kernel and initramfs in `/System/Kernel/Boot`, so kernel and system are always updated together. The
installer refuses disks under 32 GB. Only the active slot is mounted; the inactive slot, the boot partition
and the data partition must never show up as "USB drives" or be auto-mounted by devmon.

**As built:** a slot counts as filled only when `/gobo-slot.env` (a GRUB environment block with
`slot_version=`) exists at its root; it is written last by the installer and by `gobo-update`. gobo-update
formats a slot again with the same file system UUID, so the static `grub.cfg` stays valid.

## How the running system is put together

The root filesystem is an **overlay**, set up by a small dracut module (`90goboab`) before the switch to
the real root.

**As built — three layers instead of two:**

- `GOBO_DATA:/System-Overlay/upper` (+ `/work`) — every change made to system files after the install
  (settings, added programs, `/System/Index` links). Writable.
- `GOBO_DATA:/System-Overlay/install` — the machine's own settings written by the installer (accounts,
  hostname, fstab, keyboard, login screen, time zone). Read-only at run time.
- the active slot (read-only), the pristine image.
- `GOBO_DATA:/Users` — mounted as `/Users` (not inside the overlay, so resetting the overlay keeps homes).
- `GOBO_DATA:/Variable` — mounted as `/Data/Variable` (logs, caches, state).
- The data partition itself is mounted at `/System/Data`, the slot at `/System/Slot` (for gobo-update).

Why: with a single overlay, "without my system changes" and "reset" would also drop the accounts, the
hostname and the login setup, so nobody could log in afterwards. The install layer keeps the machine
working in both cases.

Consequences, accepted:

- Everything behaves as on 0.6: `sudo Compile`, `SymlinkProgram`, editing a settings file — all just work
  and persist.
- A broken change to a system file breaks both slots (the overlay is shared). Therefore the boot menu has a
  second entry per slot, **"without my system changes"**: install layer + slot, a throw-away upper layer in
  memory (the current account files are copied into it, so passwords changed after the install still work).
  `gobo-update --reset-system-changes` empties the upper layer at the next start (it is kept as
  `System-Overlay/previous-upper` until the next reset; accounts are kept). Home folders are not touched.
- Files in the overlay hide newer versions from an update. So everything machine-specific written at
  install time must be written through the overlay, and slots only ever contain the pristine image.
  **As built:** settings that are the same on every computer (wired DHCP, the A/B boot task, locale,
  resolv.conf, the power-menu sudo rule, mtab link) are part of the pristine image (`gobo-make-system`),
  so updates can change them. On the first boot of a new version (a) the initramfs deletes the generated
  caches listed in `share/gobo-update/generated-caches` from both overlay layers and from `/Data/Variable`
  (the new image's caches show through), and the boot task regenerates them only if the user added
  programs; (b) the boot task re-runs the look's `apply.sh` for every home folder (as the user), which
  keeps the user's own files and since 0.8 also their light/dark choice; (c) new folders of the image's
  `/Data/Variable` are copied to the data partition without overwriting anything.
- New system accounts that a later image adds to `/System/Settings/passwd` are hidden by the install
  layer's copy (not handled; no such change is planned).

## Boot and fallback

GRUB reads `grubenv` on `GOBO_BOOT`: `slot` (a or b), `try_slot`, `tries_left`, and **as built**
`rollback_from`. After an update: `try_slot` = the new slot, `tries_left=2`; GRUB decrements on each attempt.
While trying, GRUB adds `rd.shell=0 rd.emergency=reboot panic=10` (a slot that fails reboots instead of
waiting at a prompt) and sets GRUB's `fallback` to the default slot (a kernel that does not load falls back at
once). When the boot scripts have finished (just before the login screen or text login starts), the boot task
`gobo-update --boot-task` marks the slot good (`slot=<new>`, try variables cleared). If the tries run out,
GRUB sets `rollback_from` and boots the old slot again; the boot task turns that into a notice
(`/Data/Variable/lib/gobo-update/notice`) and the desktop (`awesome/spin/updates.lua`) shows "System update
undone" once per user. The menu always offers both slots by hand (an empty slot is listed as "Slot B:
empty" and only prints a message), plus the "without my system changes" and "safe graphics" variants.
A start "without my system changes" never marks a slot good.

## Update file and tool

- An update is one file, `GoboRefined-<version>.update`: a squashfs of the pristine system image followed
  by an 8 KiB trailer (manifest: version, image size, sha256, installed size; RSA-3072 signature of the
  manifest, base64). Produced by `spin/build-iso.sh` next to the ISO, from the same tree the installer
  installs (both run `gobo-make-system` on the live image).
- Signed with a key pair made for this project (`openssl dgst -sha256 -sign`); the public key is in the
  image (`/Programs/GoboSpin/Current/share/gobo-update/update-signing.pub.pem`), the private key stays on
  the host outside git (`vm/keys/`); for a build it is put into the build VM's RAM only. `gobo-update`
  refuses unsigned or altered files.
- `sudo gobo-update FILE` (from a USB stick or a download; a URL may come later when publishing is
  decided): verify → format the inactive slot → unpack → check → write `gobo-slot.env` → set `try_slot` →
  ask to restart. `gobo-update --status` shows both slots and their versions; `--rollback` selects the other
  slot; `--reset-system-changes` as above.
- The running slot is never written to (checked by PARTUUID, GPT name, mount table and the running slot's
  UUID before formatting).

## Installer

`gobo-install` is rewritten around this layout: partition, format, unpack the image into slot A (slot B
stays empty until the first update, shown as "empty" in the menu), create the data partition folders, then
do all configuration through the overlay (install layer). Options kept: `--answers`, `--autologin`,
`--text-login`, `--swap` (swap file on the data partition). Works on BIOS and UEFI.

In 0.8 as well: questions asked through `dialog` menus (disk, timezone and keyboard from lists) — **not done
yet**, left for the menus step. Not in 0.8: Wi-Fi during install (after the Wi-Fi menu fix of 0.6.2), install
next to another system (own later checkpoint; needs 32 GB of free space and stays the one change that can
destroy data).

## Where other kinds of programs go

`/Programs` stays native-only. If Android or Windows programs are ever added, their files live on the data
partition (`/Data/Android`, `/Data/Windows`), not under `/Programs`.

## Test plan (VM)

1. Install (UEFI and BIOS), boot, log in; all 0.6 checks still pass (`vm/input-test.sh`, desktop, USB).
2. Persistence: add a user, change a setting, `Compile` or hand-install a small program, reboot — all there.
3. Update: build a second image with a visible difference, `gobo-update`, reboot → new version, user data,
   added program and settings intact, caches fresh, look refreshed.
4. Rollback by hand (`--rollback`) and automatic (break the new slot's kernel or init on purpose → GRUB
   returns to the old slot after the tries).
5. "Without my system changes" boots with a deliberately broken settings file in the overlay.
6. Power cut during an update (kill the VM while the slot is being written) → old slot still boots.

## As built: open points (see HANDOFF.md, 0.8)

- The initramfs runs `e2fsck -p` on the data partition before mounting it, but in the VM the kernel still replayed
  the journal at mount time after a power cut: the pre-mount check does not work as intended yet.
- ext4 is made without `orphan_file` (after power cuts the kernel reported bad orphan inodes with it).
- A slot holds 8.1 GB of 12 GiB (the design's 6.7 GB figure was before OnlyOffice and later programs).
