# A/B system updates — design for 0.8

Decided 2026-11-14 (owner asked for A/B and said "decide"). This is the brief for the implementation; change
it when the prototype proves a point wrong, and say so in HANDOFF.md.

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

| # | Label | Size | Content |
|---|---|---|---|
| 1 | — | 1 MB | BIOS boot partition (GRUB core on BIOS machines) |
| 2 | `GOBO_BOOT` | 512 MB FAT32 | EFI system partition; GRUB, `grub.cfg`, `grubenv` (same partition on BIOS) |
| 3 | `GOBO_A` | 12 GB ext4 | system slot A, mounted read-only |
| 4 | `GOBO_B` | 12 GB ext4 | system slot B, mounted read-only |
| 5 | `GOBO_DATA` | rest (8 GB or more) ext4 | everything that survives updates |

No recovery partition: the other slot and the install USB stick are the recovery. Each slot carries its own
kernel and initramfs in `/System/Kernel/Boot`, so kernel and system are always updated together. The
installer refuses disks under 32 GB. Only the active slot is mounted; the inactive slot, the boot partition
and the data partition must never show up as "USB drives" or be auto-mounted by devmon.

## How the running system is put together

The root filesystem is an **overlay**: the active slot (read-only) below, a folder on the data partition
above. Set up by a small hook in the initramfs before the switch to the real root.

- `GOBO_DATA:/System-Overlay/upper` + `/work` — every change made to system files (settings, added programs,
  `/System/Index` links).
- `GOBO_DATA:/Users` — mounted as `/Users` (not inside the overlay, so resetting the overlay keeps homes).
- `GOBO_DATA:/Variable` — mounted as `/Data/Variable` (logs, caches, state).

Consequences, accepted:

- Everything behaves as on 0.6: `sudo Compile`, `SymlinkProgram`, editing a settings file — all just work
  and persist.
- A broken change to a system file breaks both slots (the overlay is shared). Therefore the boot menu has a
  second entry per slot, **"without my system changes"** (overlay not applied, a throw-away one in memory
  instead), and `gobo-update --reset-system-changes` empties the overlay. Home folders are not touched.
- Files in the overlay hide newer versions from an update. So everything machine-specific written at
  install time (accounts, fstab, hostname, keyboard, login settings, sudoers rule) must be written through
  the overlay, and slots only ever contain the pristine image. On the first boot of a new version a hook
  (a) deletes generated caches from the overlay (ld.so.cache, font, icon, mime, desktop-file and pixbuf
  caches — keep the list in one file) and regenerates them, (b) re-runs the look's `apply.sh` for every
  home folder, because the look's files live in the homes.

## Boot and fallback

GRUB reads `grubenv` on `GOBO_BOOT`: `slot` (a or b), `try_slot`, `tries_left`. After an update: `try_slot`
= the new slot, `tries_left=2`; GRUB decrements on each attempt. When the desktop login screen (or text
login) is reached, a boot task marks the slot good (`slot=<new>`, try variables cleared). If the tries run
out, GRUB boots the old slot again and the user gets a notification that the update was rolled back. The
menu always offers both slots by hand, plus the "without my system changes" and "safe graphics" variants.

## Update file and tool

- An update is one file, `GoboRefined-<version>.update`: a squashfs of the pristine system image, with a
  manifest (version, size, sha256) and a signature. Produced by `spin/build-iso.sh` next to the ISO, from
  the same tree the installer installs.
- Signed with a key pair made for this project (`openssl dgst -sha256 -sign`); the public key is in the
  image, the private key stays on the host outside git. `gobo-update` refuses unsigned or altered files.
- `sudo gobo-update FILE` (from a USB stick or a download; a URL may come later when publishing is
  decided): verify → format the inactive slot → unpack → check → set `try_slot` → ask to restart.
  `gobo-update --status` shows both slots and their versions; `--rollback` selects the other slot.
- The running slot is never written to.

## Installer

`gobo-install` is rewritten around this layout: partition, format, unpack the image into slot A (slot B
stays empty until the first update, shown as "empty" in the menu), create the data partition folders, then
do all configuration through the overlay. Options kept: `--answers`, `--autologin`, `--text-login`,
`--swap` (swap file on the data partition). Works on BIOS and UEFI.

In 0.8 as well: questions asked through `dialog` menus (disk, timezone and keyboard from lists). Not in 0.8:
Wi-Fi during install (after the Wi-Fi menu fix of 0.6.2), install next to another system (own later
checkpoint; needs 32 GB of free space and stays the one change that can destroy data).

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
