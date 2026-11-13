# Handoff

Updated 2026-11-12 (evening). Direction: **modernized spin, path of least resistance** — see `docs/goals.md`.

## Where things stand

- **Installer works on BIOS and UEFI.** `installer/gobo-install` installs 017.01 to a whole disk in ~3 minutes;
  the result boots from disk, brings up wired network, and starts the desktop after login. Verified end to end in
  the VM for BIOS/MBR and for UEFI/GPT (UEFI run was started from a BIOS-booted live session with `--firmware efi`,
  so the optional `efibootmgr` step has not been exercised).
- **Look done (first pass): `look/gobo11/`.** Awesome theme with bottom taskbar, centred launcher/pinned/running
  apps, flat title-bar buttons, rounded windows, drawn wallpaper, restyled terminal, GTK dark. `apply.sh` installs it
  into a home directory; the installer runs it when `gobo11/` sits next to `gobo-install`. Dark is the default;
  `MODE = "light"` in `theme.lua` is written but never looked at.
- **Second display: written, NOT tested.** rc.lua now builds a taskbar per screen (also hot-plugged) and
  `displays.sh` extends the desktop with `xrandr` — but **017.01 does not ship the `xrandr` command** (its XRandR
  package is only the library), so the script cannot work until that tool is added.
- **ISO: built — see the last section.** Background: The stock ISO is isolinux + `efiboot.img` + one `gobolinux-live.squashfs`; the live session
  mounts the medium at `/Data/Variable/run/initramfs/live`, so extra files on the ISO are reachable without
  rebuilding the squashfs. No ISO authoring tool (xorriso/mkisofs) exists on the host or on the GoboLinux image.
- `dist/gobo-spin.tgz` = installer + look, for use from a second USB stick with the stock ISO.

## What the installer does differently from upstream

- Reuses upstream `ProfileInstall` for the copy (all of `/Programs` except `LiveCD`).
- Writes `fstab` and a static `grub.cfg` (always `/System/Kernel/Boot/grub/grub.cfg`); never calls `grub-mkconfig`.
- UEFI: builds `EFI/BOOT/BOOTX64.EFI` with `grub-mkimage` and an embedded search-by-UUID script. `grub-install`
  is unusable for EFI here: `grub-probe` sees `/System/Kernel/Devices/sda1`, finds no partition map, and the
  loader ends in "unknown filesystem" / a bare `grub>` prompt.
- Passwords via `openssl passwd -6` + `usermod -p`: **`chpasswd` on 017.01 exits 0 and changes nothing**.
- Adds `dhcpcd -b eth0` to BootUp (stock boot only raises loopback) and sets `ClockMode=GMT`.
- Desktop start: no display manager on the image (stock `Graphic` script calls a missing `kdm`), so login on
  tty1 runs `startx`. The console is `/System/Kernel/Devices/tty1`, not `/dev/tty1`.

## Not tested / known gaps

- `--autologin`, `--swap`, interactive prompts (tests used `--answers`), NVMe naming, real hardware, Wi-Fi.
- Whole-disk only: no dual boot, no manual partitioning.
- VirtualBox EFI boots the disk before the DVD once a loader is installed: switch the VM to BIOS to boot the ISO.

## Lab plumbing (how to drive the VM without the clipboard)

- `node vm/serve.js` serves `vm/serve/` and `installer/` to the guest at `http://10.0.2.2:8766/` (CRLF stripped).
- NAT port forward host 2222 → guest 22 is set on the VM. In the live session type:
  `wget -qO- http://10.0.2.2:8766/lab-ssh.sh | sh` — then `vm/ssh.sh '<command>'` works from the host.
- Unattended test install: in the guest, fetch `gobo-install` and `lab-answers.env`, run
  `./gobo-install --answers lab-answers.env`. `vm/serve/lab-answers.env` holds the lab-only test login.
- Keystrokes/screenshots: `VBoxManage controlvm … keyboardputstring|keyboardputscancode|screenshotpng`.
  Leave long pauses at login prompts; do not type in the VM window at the same time.

## VM snapshots

- `not even installed` — live session running, empty disk.
- `installed-manual-grub` — stock Installer + hand-written grub.cfg (the original painful install).
- `thin-installer-ok` — first working gobo-install result, stock look.
- `look-installed-bios` — gobo-install + gobo11, BIOS; sshd enabled at boot (lab tweak); 2 monitors configured.
- `look-installed-efi` — gobo-install + gobo11, UEFI. **Current.**

## Next

1. Get the user's decision on downloading xrandr/xorriso sources (or another route).
2. Second-display test (VM `--monitor-count 2`), then ISO build and boot test in BIOS and UEFI.
3. Polish: light mode check, Gobo status widgets still use neon colours, alt-tab switcher colours.

## Read first next session

`docs/goals.md`, this file, `installer/gobo-install`, `docs/installation-bug-report.md` (history).

## Spin ISO: built and tested in the VM (2026-11-12)

**`dist/GoboLinux-017.01-spin.iso`** (2.4 GB, sha256 in `dist/GoboLinux-017.01-spin.iso.sha256`). It is the stock
017.01 ISO with a repacked live image; boot records (BIOS isolinux, UEFI `efiboot.img`, isohybrid MBR+GPT) are
replayed unchanged from the stock ISO by xorriso.

What is added to the live image (and therefore to every install, since the installer copies `/Programs`):
- `/Programs/GoboSpin/1.0` — `bin/gobo-install` and `share/gobo11` (the look).
- `/Programs/XRandR-Tool/1.5.2` — `xrandr`, built from the X.Org source (017.01 ships only the library).
- The gobo11 look applied to the EnhancedSkel skeleton, so the live user and all new users get it.
- English welcome text pointing at `gobo-install`.

Verified in the VM, driving the installer by keyboard exactly as a user would:
- BIOS: boot ISO -> `gobo-install` -> install -> boots from disk -> desktop, network, `xrandr` present. (First ISO build.)
- UEFI: same with the final ISO, live session booted in UEFI mode; `efibootmgr` registered a "GoboLinux" boot
  entry; boots from disk to the desktop with the chosen timezone.
- Second screen: rc.lua logic verified only with awesome's fake screens.

NOT verified: real hardware of any kind; booting the ISO from a USB stick (only as a virtual DVD); Wi-Fi; NVMe
disks; a physical second monitor (detection and `displays.sh`); `--autologin`; `--swap`; light mode;
non-English welcome texts still mention the old `Installer`.

### Rebuilding the ISO

1. Host: `node vm/serve.js`; refresh `vm/serve/gobo11.tgz` (`cd look && tar czf ../vm/serve/gobo11.tgz gobo11`)
   and `vm/serve/build-iso.sh` (copy of `spin/build-iso.sh`).
2. Restore VM snapshot `iso-build-env-2`, firmware EFI, **no ISO attached**, boot from disk (sshd starts at boot).
3. Hot-attach the stock ISO, then in the VM: `bash /Data/Build/build-iso.sh` (fetches from the host, ~5 min).
   Do not wait on it with `pgrep -f build-iso.sh` over ssh — that matches the waiting shell itself.
4. `scp` `/Data/Build/GoboLinux-017.01-spin.iso` to `dist/`.

### VM snapshots added today

`look-installed-bios`, `look-installed-efi`, `iso-build-env`, `iso-build-env-2` (build environment),
`iso-v1-installed-bios`, `iso-final-installed-efi` (**current**).

### Next ideas

Real-PC test by the user; a physical two-monitor test; restyle the Gobo status widgets and alt-tab switcher
(still neon colours); a login screen instead of text login; a file manager and settings tool.

### Snapshot cleanup (2026-11-12, late)

Six superseded snapshots were deleted at the user's request (VM folder 68 GB -> 34 GB). Remaining:
`not even installed`, `iso-build-env-2` (needed to rebuild the ISO), `iso-final-installed-efi` (current).
Snapshot names listed earlier in this file that are not among these three no longer exist. VM is powered off.

## Next iteration (decided 2026-11-13)

- The user ran ISO 0.1 on a **real PC and it worked**.
- Goal: **the user's own daily use**. All items on the ideas list are wanted, over several sessions,
  in the order and with the checkpoints in **`docs/roadmap.md`** — read that first.
- Open-source software may be downloaded and compiled into the ISO freely; list what was added afterwards.
- Not started. Next up: stage 0 (git, spin name, bug-report drafts), then stage 1 (launcher, power menu, lock,
  neon leftovers, light mode).

## Stage 0 and stage 1 done — ISO 0.2 (2026-11-13)

- Workspace is a git repository (`main`); ISOs, the VM, `upstream/` and lab secrets are ignored.
- `docs/upstream-bugs/` holds four draft reports (not posted). Spin name still undecided.
- New in the look (`look/gobo11/awesome/spin/`): `launcher.lua` (search), `power.lua` (lock, log out, restart,
  shut down, dark/light), `status.lua` (flat battery/volume/brightness), `alttab.lua` (stock switcher, theme
  colours). Category menu restyled. Start button: left click = category menu, right click = search.
  Keys: Win+R / Win+P / Alt+F2 search, Win+W menu, Win+L lock, Ctrl+Alt+Del power menu.
- Installer additions: sudo rule so group `sys` can run shutdown/reboot/poweroff/halt without a password;
  console logs out when the desktop session ends (unless X died within 20 s).
- **`dist/GoboLinux-017.01-spin-0.2.iso`** built with `spin/build-iso.sh` (VERSION=0.2). Verified in the VM by
  keyboard-driven installs in BIOS and UEFI mode; on the BIOS install also search, log out and shut down.
  Mouse clicks (start button, power menu buttons) could not be simulated — only keyboard paths were exercised.

Lab lessons:
- `vm/push-look.sh` pushes the look to the VM user and reloads; `vm/lua.sh '<lua>'` runs Lua in the desktop.
  The X display is not always `:0` — `lab-desktop.sh` reads it from the awesome process.
- In the menu, Right on "Search applications..." activates it; send test keys slowly.
- VirtualBox UEFI boots the disk, not the DVD, when the disk has a loader/boot entry. Before a UEFI ISO test on
  the build disk: delete `GoboLinux` entries with `efibootmgr -B` and remove `EFI/BOOT/BOOTX64.EFI` from the ESP
  (the snapshot keeps the build environment intact). Always screenshot before typing install answers.
- XSecureLock needs `XSECURELOCK_NO_COMPOSITE=1` here, or the taskbar area shows through the lock screen.

VM snapshots now: `not even installed`, `iso-build-env-2` (build env), `iso-final-installed-efi` (0.1, can be
deleted), `iso-0.2-installed-efi` (**current**, powered off).

Next: user tries ISO 0.2 on the real PC (checkpoint 1). Then stages 2+3 together (fonts/icons kept minimal).
