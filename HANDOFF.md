# Handoff

Updated 2026-11-14. The spin is now called **GoboRefined** (an unofficial spin of GoboLinux 017.01); current ISO: **`dist/GoboRefined-0.6.iso`** (see the last section; 0.5 is kept). Direction: **modernized spin, path of least resistance** (see `docs/goals.md`).

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

(Current procedure, updated for 0.5; the snapshot names below are the ones that exist now.)

1. Host: `node vm/serve.js` on port 8766; refresh `vm/serve/gobo11.tgz` (`cd look && tar czf ../vm/serve/gobo11.tgz gobo11`),
   `vm/serve/lxdm-files.tgz` (`cd spin && tar czf ../vm/serve/lxdm-files.tgz --exclude=render-title.sh lxdm`),
   `vm/serve/build-iso.sh` (identical copy of `spin/build-iso.sh`), `vm/serve/gobo-command-not-found`,
   `vm/serve/software-install.txt` (copy of `docs/software-install.md`); `vm/serve/welcome.src` is edited in place.
2. Restore VM snapshot `iso-build-env-5`, firmware EFI, **no ISO attached**, boot from disk (sshd starts at boot).
3. Hot-attach the stock ISO, then in the VM: `bash /Data/Build/build-iso.sh` (fetches from the host; ~10 min with
   ONLYOFFICE). Do not wait on it with `pgrep -f build-iso.sh` over ssh — that matches the waiting shell itself;
   poll `tail /Data/Build/build-0.5.log` for `BUILD-DONE` instead (run it with nohup and a log file).
4. `scp` `/Data/Build/GoboRefined-$VERSION.iso` to `dist/`, write the `.sha256`, compare with the build's output.

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

## Stage 2 (fonts and icons) done in the look and build VM — ISO 0.3 not built yet (2026-11-13)

- Fonts: **Inter 4.1** (UI, static TTFs) and **JetBrains Mono 2.304** (terminal, hotkeys). Icons: **Papirus 20260801**,
  trimmed to sizes 16–64 (no @2x/HiDPI, 8, 18, 42, 84, 96, 128); Papirus-Dark/Papirus-Light follow the dark/light mode.
- Packaged as `/Programs/Inter/4.1`, `/Programs/JetBrains-Mono/2.304`, `/Programs/Papirus-Icon-Theme/20260801` in the
  build VM; tarballs in `spin/programs/` (note: `spin/programs/*.tgz` is **not** gitignored; Papirus is 37 MB).
- `spin/build-iso.sh`: VERSION=0.3, copies + `SymlinkProgram`s the new programs, runs `fc-cache` and
  `gtk-update-icon-cache` in the rootfs. **Rebuild from snapshot `iso-build-env-3`** (has the programs), not -2.
- Look: theme fonts, `icon_theme`, taskbar icon fallback by window class, GTK settings, `fontconfig/fonts.conf`
  (sans-serif -> Inter, monospace -> JetBrains Mono), urxvt font + Ctrl+Alt+0..9 sizes, `apply.sh` now replaces an
  older `.Xresources` block. Screenshots `docs/screenshots/0.3-*`. Inventory for stage 3: `docs/stage3-inventory.md`.
- Snapshot `iso-build-env-3` was taken **with the VM powered off**. A live snapshot (`--live`) of this VM never
  finished (state file kept growing) and the VM had to be killed; do not take live snapshots here.

## Stage 3 (desktop programs) done in the look and build VM — ISO 0.4 not built yet (2026-11-13)

Built by hand (`./configure --prefix=/Programs/<Name>/<Version>`, settings in `/Programs/<Name>/Settings`,
`SymlinkProgram`) with **`spin/build-programs.sh <step>`** (steps: menu-cache libfm pcmanfm pavucontrol lxrandr lxdm;
sources in `/Data/Build/src3`). gcc 14 needs `-Wno-error=incompatible-pointer-types` etc. for these 2015–2019 sources.
Tarballs in `spin/programs/` (gitignored). Together ~9.4 MB installed, ~2.0 MB as tgz.

| Program | Version | Notes |
|---|---|---|
| Menu-Cache | 1.0.2 | dependency of LibFM (LibFM is first built "extra only" for it) |
| LibFM | 1.2.5 | GTK 3, no libexif, no custom actions (Vala); "Shortcut Editor" menu entry hidden |
| PCManFM | 1.2.5 | GTK 3; "Desktop Preferences" entry hidden (Awesome owns the wallpaper; PCManFM never runs `--desktop`) |
| PaVuControl | 4.0 | autotools release; gtkmm-3, libpulse, libcanberra-gtk3 were already on the image |
| LxRandr | 0.3.1 | GTK 3; uses the `xrandr` tool from 0.1; icon changed to `preferences-desktop-display` |
| LXDM | 0.5.3 | GTK 3, PAM, no ConsoleKit; spin files in `spin/lxdm/`; see **`docs/login-screen.md`** |

Downloads (all built from source, fetched in the guest):

| Name | Version | URL | Licence |
|---|---|---|---|
| libfm | 1.2.5 | https://downloads.sourceforge.net/pcmanfm/libfm-1.2.5.tar.xz | GPL-2.0 (COPYING); most library sources carry LGPL-2.1+ headers |
| menu-cache | 1.0.2 | https://downloads.sourceforge.net/lxde/menu-cache-1.0.2.tar.xz | LGPL-2.1+ |
| pcmanfm | 1.2.5 | https://downloads.sourceforge.net/pcmanfm/pcmanfm-1.2.5.tar.xz | GPL-2.0+ |
| pavucontrol | 4.0 | https://freedesktop.org/software/pulseaudio/pavucontrol/pavucontrol-4.0.tar.xz | GPL-2.0+ |
| lxrandr | 0.3.1 | https://downloads.sourceforge.net/lxde/lxrandr-0.3.1.tar.xz | GPL-2.0+ |
| lxdm | 0.5.3 | https://downloads.sourceforge.net/lxde/lxdm-0.5.3.tar.xz | GPL-3.0+ |
| GoboNet | 0.12 | https://github.com/gobolinux/GoboNet/archive/refs/tags/0.12.tar.gz | GPL-3.0 (read only to check its Makefile; not built) |

MD5 of the five LXDE/PCManFM tarballs match the upstream Recipes; pavucontrol is the .xz of the same release.

Look (`look/gobo11/`):
- Taskbar: pinned **Files** button between Terminal and Firefox; **Win+E** opens PCManFM.
- Volume icon: left click opens PaVuControl (floating, above the icon), right/middle click mute, wheel = volume.
- Menu → Desktop → **Displays...** opens LxRandr; "Detect Displays" now forces the automatic layout
  (`displays.sh --auto`); at login `displays.sh` uses a layout saved with LxRandr's Save, if any.
- Category menu keeps entries whose icon is not found (generic icon) instead of dropping them.
- `libfm/libfm.conf` and `pcmanfm/default/pcmanfm.conf` defaults, copied by `apply.sh` only if absent
  (places: Home, Desktop, Filesystem Root; no volume list — the VM showed proc/sys/pts... from fstab otherwise).
- GTK apps follow `gtk-3.0/settings.ini` (dark/light + Papirus-Dark/-Light); checked in both modes.

`spin/build-iso.sh`: VERSION=0.4, copies + `SymlinkProgram`s the six programs, runs `update-mime-database`,
and sets the setuid bit on `gobonet_backend` (see **`docs/wifi-notes.md`**). `vm/serve/build-iso.sh` is identical.
**Rebuild from snapshot `iso-build-env-4`.** The rootfs steps of build-iso were not run (no ISO built).

Screenshots `docs/screenshots/0.4-*`: file manager (dark), sound control (dark), displays (dark), light mode
(file manager + sound), login greeter, network menu.

Not tested: PCManFM file operations beyond browsing (copy/move/trash, removable media — there is no udisks/gvfs,
so no automount and no Trash view), PaVuControl with real playback streams, LxRandr Apply/second monitor,
LXDM items listed in `docs/login-screen.md`, anything on real hardware. PCManFM 1.2.5 does not quit on SIGTERM
(`pkill pcmanfm` leaves a hung window; closing the window or ending X is fine).

Lab lessons:
- `vm/lua.sh 'root.fake_input("motion_notify", false, X, Y)'` then `root.fake_input("button_press", 1)` /
  `("button_release", 1)` **clicks with the mouse** inside the Awesome desktop (taskbar, menus, windows).
- zsh is root's shell in the guest: an unmatched glob (`*.tgz`) aborts the whole `vm/ssh.sh` command line.
- To try LXDM at boot in the VM: append the inittab line from `docs/login-screen.md` (a copy of the original is
  `/Data/Build/inittab.before-lxdm-test`); the snapshot has text login (inittab restored).

VM snapshots: `iso-build-env-4` (= -3 + the six programs, **current**, taken powered off).

## Stage 3 checkpoint — ISO 0.4 built and install-tested in the VM (2026-11-13, evening)

**`dist/GoboLinux-017.01-spin-0.4.iso`** (2,465,333,248 bytes), sha256
`0c9a21f8d84d6e9b0cd1275faa0a7509ea298a797040a819dc0e611cc68f8946` (`.sha256` next to it, matches the build VM's).
Built from snapshot `iso-build-env-4` with `spin/build-iso.sh` unchanged (first build succeeded, no fixes needed).

Installs from it, all in the VM:
- **UEFI, interactive, defaults** (typed by keyboard; layout `pl`, Europe/Warsaw): boots to the LXDM greeter;
  greeter X uses layout pl (`setxkbmap -query`, AltGr+A gives "ą"); wrong password -> back to "User:", next
  login works; desktop with Inter/JetBrains Mono/Papirus-Dark; by **simulated mouse clicks**: Files button,
  volume icon -> PaVuControl, dots left click -> category menu -> Desktop -> Displays... -> LxRandr (Cancel
  click closes it), dots right click -> search, search's power button -> power menu; Lock (unlocked by typing
  the password), Light mode / Dark mode, Log out (greeter returns; only PulseAudio stays, and it exits on its
  own after its 20 s idle time), Restart (fresh boot back to the greeter), Shut down (VM off in ~6 s).
  Win+E opens PCManFM. `gobonet_backend` is `-rwsr-xr-x`; eth0 gets 10.0.2.15 by DHCP.
- **BIOS, `--autologin --swap 1024`** (answers file): boots straight to the desktop; `/Data/Variable/swap`
  1024 MB active. Log out -> the greeter asks for login and password (LXDM autologins only at its first start).
- **BIOS, `--text-login`**: no LXDM, no inittab line, no keyboard file; tty1 login starts the desktop, Log out
  returns to the tty1 login prompt.

Not tested: the greeter's Quit button (reboot/shut down from the login screen), real Wi-Fi, PaVuControl with
playback, LxRandr Apply / a second monitor, interactive answers for the BIOS runs (answers file used), real hardware.
Observed, not fixed: a fresh install's output volume shows 4% in PaVuControl (VirtualBox HDA; may differ on a
PC); the installer's closing line says "Log in as 'lab' and the desktop starts" even with `--autologin`, and its
summary does not mention the login method (cosmetic).

Lab lessons:
- Git Bash rewrites a lone `/`-path in `VBoxManage ... keyboardputstring` (`Europe/Warsaw` arrived as
  `EuropeC:/Program Files/Git/Warsaw`). Set `MSYS_NO_PATHCONV=1` for keyboard helpers.
- The installed system has no sshd at boot: log in as root on tty2 (Ctrl+Alt+F2) and run the `lab-ssh.sh`
  one-liner, then Ctrl+Alt+F7 back to the greeter/desktop. `/tmp/lab-desktop.sh` must be fetched again after
  each boot for `vm/lua.sh`.
- Taskbar buttons move when windows open/close (the centre group re-centres): with no windows, dots=572,
  Terminal=616, Files=660 at y=776 (1280x800); screenshot before clicking.
- Before booting the ISO in UEFI mode, the old loader must really be gone: `/System/Kernel/ESP` was not mounted
  on the build disk, so mount `/dev/sda1` and remove `EFI/BOOT` there. In BIOS mode the VM boots the DVD
  first even when the disk has GRUB.

VM snapshots now: `not even installed`, `iso-build-env-2`, `iso-final-installed-efi`, `iso-0.2-installed-efi`,
`iso-build-env-3`, `iso-build-env-4` (build env for 0.4), **`iso-0.4-installed-efi`** (current, powered off:
UEFI default install of ISO 0.4, user lab, LXDM). Rebuild 0.4 from `iso-build-env-4`.

Next: the user tries ISO 0.4 on the real PC (checkpoint 3), then stage 4 (boot experience).

## ISO 0.4 feedback fixed in the build VM — ISO 0.5 not built yet (2026-11-14)

The user ran 0.4 on a real PC (NVIDIA, works) and reported six problems. All were worked on in the
build VM; **rebuild 0.5 from snapshot `iso-build-env-5`** with `spin/build-iso.sh` (VERSION=0.5;
`vm/serve/build-iso.sh` identical). Before building: refresh `vm/serve/gobo11.tgz`
(`vm/push-look.sh` does it), and keep `vm/serve/` copies of `spin/gobo-command-not-found`,
`docs/software-install.md` (as `software-install.txt`), `spin/patches/*.patch`, `spin/build-programs.sh`.

| # | Report | State | What changed |
|---|---|---|---|
| 1 | Double click on title bar does not maximize | done | `rc.lua`: 2nd press within 300 ms toggles maximize; moving starts only after the pointer moves > 3 px (a plain click on a window at the top edge used to trigger awful's edge snap and resize it to half the screen) |
| 2 | Right click does not paste in the terminal | done | `look/gobo11/urxvt/gobo-paste` (perl ext, installed to `~/.urxvt/ext`) + stock `selection-to-clipboard`: select = copy (PRIMARY and CLIPBOARD), right click = paste CLIPBOARD, Shift+right click = old extend-selection, Ctrl+Shift+C/V; `Xresources.append` |
| 3 | USB stick: no pop-up, `/Mount/Media` dangling link | done | Udevil 0.4.4 (+ GoboLinux patch), devmon from `xinitrc`, `awesome/spin/usb.lua` (notification + taskbar drive icon: Open / Safely remove), "USB drives" bookmark in PCManFM, installer removes the `/Mount/Media/Media` link |
| 4 | TP-Link Archer TX20U Plus Wi-Fi | partly (no hardware) | USB-ModeSwitch 2.6.1 + udev rule for `0bda:1a2b`; RTL8852AU driver (lwfinger, 865ab0f) built for 6.12.16-Gobo; see `docs/wifi-notes.md` |
| 5 | OnlyOffice wanted | done | ONLYOFFICE Desktop Editors 10.0.0 official x64 tarball under `/Programs/OnlyOffice/10.0.0`; default for docx/xlsx/pptx/odt/ods/odp via `~/.config/mimeapps.list` from the look |
| 6 | Installing software is confusing | investigated, hint fixed | `spin/gobo-command-not-found` replaces the hint's `InstallPackage` with `sudo Compile`; `docs/software-install.md` |

Also: installer summary now has a `login` line (login screen / text login / automatic login) and the
closing line matches the login method; `bash -n` clean, behaviour otherwise unchanged.

### Findings worth remembering

- **libudev "udev" monitors do not work on GoboLinux.** libudev only subscribes to udevd's events
  if `/dev` itself is a devtmpfs mount; here `/dev` is a link to `/System/Kernel/Devices`, so
  `udevadm monitor --udev` (and udevil's monitor) receive nothing. `spin/patches/udevil-0.4.4-gobo-monitor.patch`
  makes udevil listen to kernel events and wait for udevd. Anything else using libudev monitors
  (Xorg input hotplug?) may be affected the same way — not checked.
- devmon looked for `/dev/sdX` in `/proc/mounts`, which lists `/System/Kernel/Devices/sdX`, so a
  pulled-out stick stayed mounted; same patch.
- The kernel build tree (`/lib/modules/6.12.16-Gobo/build`) is complete but lacks
  `include/config/kernel.release`: out-of-tree modules build only with `KERNELRELEASE=6.12.16-Gobo`
  on the make command line.
- `/System/Index/lib/modules` is a link into the Linux program, so modules from other programs are
  linked by hand into `Linux/Current/lib/modules/<krel>/updates/` and `depmod` is run (build-iso does it).
- The 017 binary package server lists 2 packages; `InstallPackage` is a dead end. `sudo Compile X`
  works (tested with Figlet as root: it clones the 500 MB recipe store first). No JDK recipe exists.
- Kernel has vfat, exfat, ntfs3 as modules; no FUSE NTFS tools. udevil's NTFS mounts go to ntfs3
  through a `mount.ntfs` helper (the kernel registers only `ntfs3`). Only vfat was mounted in tests.
- GTK's file chooser (Save As in OnlyOffice and others) lists proc, pts, shm, sys, efivars, ESP in
  its side pane (no gvfs); not fixed.

### Not tested (needs the real PC)

The Wi-Fi mode switch and driver with the adapter; exfat/NTFS sticks (no mkfs tools on the image);
ONLYOFFICE on NVIDIA (VM uses vmwgfx); right-click paste inside programs that use the mouse
themselves (mc, htop: right click now pastes there too — urxvt gives extensions no way to tell);
LXDM log-out path stopping devmon (tested only the console `startx` path, where Awesome's exit
handler stops it).

### Size added (installed / in `spin/programs/`)

Udevil 0.5 MB / 0.1 MB; USB-ModeSwitch 0.1 MB / 0.03 MB; RTL8852AU 9.6 MB / 2.5 MB;
**OnlyOffice 1.2 GB / 422 MB** (zstd ~370 MB, so the squashfs and ISO grow by roughly 0.35–0.4 GB).

### Downloads (0.5)

| Name | Version | URL | Licence |
|---|---|---|---|
| udevil (+ devmon) | 0.4.4 | https://github.com/IgnorantGuru/udevil/archive/refs/tags/0.4.4.tar.gz | GPL-3.0 |
| usb-modeswitch | 2.6.1 | https://www.draisberghof.de/usb_modeswitch/usb-modeswitch-2.6.1.tar.bz2 | GPL-2.0+ |
| rtl8852au | git 865ab0f (2024-05-06) | https://github.com/lwfinger/rtl8852au | GPL-2.0 (driver; contains Realtek firmware as C arrays) |
| ONLYOFFICE Desktop Editors | 10.0.0 | https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v10.0.0/onlyoffice-desktopeditors-x64.tar.xz | AGPL-3.0 (bundles third-party libs: Qt 5, CEF, ICU...) |
| GoboLinux Recipes (test only, not in image) | git | https://github.com/gobolinux/Recipes | GPL-2.0 |
| figlet (test only, removed) | 2.2.4 | ftp://ftp.figlet.org/pub/figlet/program/unix/figlet-2.2.4.tar.gz | BSD-3-Clause |

### Lab notes

- VM now has an xHCI USB controller and a storage controller "USB" with
  `vm/GoboLinux-017.01/usbstick.vdi` (256 MB, FAT32 "GOBOSTICK"). Hot-plug works:
  `VBoxManage storageattach GoboLinux-017.01 --storagectl USB --port 0 --device 0 --medium none`
  and again with `--type hdd --medium <path>`. The build disk sees it as `/dev/sdb`.
- xsecurelock locks the lab desktop after 10 idle minutes (simulated input does not count); a black
  screenshot means locked: `pkill xsecurelock; su lab -c "DISPLAY=:0 xset s off"`.
- **Screenshot tty1 before typing a login**: in this build VM a logout from awesome can leave the zsh
  on tty1 running, and typed credentials then land in the shell (visible on screen).
- `vm/lua.sh` code is wrapped in single quotes: use double quotes inside the Lua.
- `xclip -i` over `vm/ssh.sh` keeps the ssh session open unless its output is redirected.

VM snapshots: `iso-build-env-5` (= -4 + Udevil, USB-ModeSwitch, RTL8852AU, OnlyOffice, the 0.5 look
for `lab`, updated LXDM PostLogout; taken powered off). **Current.**

## Name GoboRefined + ISO 0.5 built and install-tested in the VM (2026-11-14)

**Name.** The user named the spin **GoboRefined**; it is always shown as an unofficial spin of GoboLinux 017.01.
Applied where a user sees the product name:
- Login screen title: `spin/lxdm/Gobo11/login.png` now reads "GoboRefined" with the line "an unofficial spin of
  GoboLinux 017.01" (the old title was this image, not text; redraw it with `spin/lxdm/render-title.sh` in the
  build VM). `spin/build-iso.sh` now copies the theme files from the host (`lxdm-files.tgz`) into the rootfs, so
  the title no longer depends on the build VM's `/Programs/LXDM` copy (snapshot `iso-build-env-5` still holds the
  old image there). That build-iso step was checked on its own in the build VM, not in a full build.
- GRUB entries written by `gobo-install`: "GoboRefined 0.5 (GoboLinux 017.01)" and "... (safe graphics)"; the
  version comes from `/Programs/GoboSpin/Current/share/spin-version` (no version when run from a checkout).
  Installer messages: disk question, "About to install GoboRefined 0.5, an unofficial spin of GoboLinux 017.01:",
  "GoboRefined is installed on /dev/sda.", the header comment shown by `--help`.
- Live welcome text (`vm/serve/welcome.src`), GoboSpin's `Description`, ISO file name `GoboRefined-$VERSION.iso`,
  `README.md`, `dist/README.md`, `docs/roadmap.md`, `docs/software-install.md` title, `docs/login-screen.md`.
- Deliberately unchanged: ISO volume label `GOBOLINUX_LIVE_INSTALLER`, partition/filesystem label `GoboLinux`,
  `/Mount/GoboLinux`, the efibootmgr label "GoboLinux", `/Programs/GoboSpin`, the `gobo11` look, VM and snapshot
  names, the default hostname `gobolinux`, the stock isolinux/UEFI boot menu of the live ISO (replayed unchanged
  from the stock ISO), upstream names (GoboNet, GoboLinux Recipes...). `dist/gobo-spin.tgz` (0.1-era installer +
  look for use with the stock ISO) was not rebuilt.

**ISO.** `dist/GoboRefined-0.5.iso`, 2,860,646,400 bytes, sha256
`b35ac96720a1454ba24d45243084a5f4a60c17026c2f43af39f1acc42163ca0b` (`.sha256` next to it; matches the build VM).
Two builds were made; the first (sha256 4375dcc1...) was replaced after the search bug below was found.
The 0.4 ISO and its checksum were removed from `dist/`.

**Bug found and fixed (look):** after the search window (right click on dots / Win+R) was closed by a click
outside it or with its power button, every later search opened without keyboard input until the next login.
Cause: `launcher.hide()` and `power.hide()` called the bare C `keygrabber.stop()`, while the search prompt runs
on `awful.keygrabber`; awful's grabber stack then believed a grabber was still running and never grabbed the
keyboard again. Fixed in `look/gobo11/awesome/spin/launcher.lua` (`awful.keygrabber.stop()`) and `power.lua`
(its own grabber via `awful.keygrabber.run/stop`). Probably present since 0.2 (0.4's tests never typed into a
search opened after such a close). Verified on the final ISO (UEFI and the autologin BIOS install).

### Tests of the final ISO (VM; keyboard and simulated mouse)

| Check | Result | Evidence |
|---|---|---|
| A UEFI install by keyboard, defaults, layout pl | pass | summary "About to install GoboRefined 0.5 ..." + login line; `0.5-installed-installer.png` |
| A GRUB shows the new name | pass | `0.5-installed-grub.png`; grub.cfg menuentries |
| A greeter titled GoboRefined, login to desktop | pass | `0.5-installed-greeter.png`, `0.5-installed-desktop.png` |
| A Win+E / Files button | pass | both open a Pcmanfm client |
| A volume icon -> sound control | pass | Pavucontrol client |
| A dots left = menu, right = search (+ typing) | pass | menu screenshot; search filters "only" -> ONLYOFFICE |
| A Displays entry | pass | Lxrandr client |
| A Lock + unlock | pass | xsecurelock running, prompt shown, password unlocks |
| A Log out -> greeter, Restart -> greeter, Shut down | pass | greeter after each; sshd gone after restart; VM off within seconds after Shut down |
| A light/dark toggle | pass | light and dark screenshots |
| A wired DHCP | pass | eth0 10.0.2.15/24 |
| B1 title bar double click / single click / drag | pass | 720x512 -> 1280x752 max -> 720x512; single click no change; drag moves |
| B2 select = copy, right click paste, Ctrl+Shift+C/V | pass | xclip shows PRIMARY+CLIPBOARD; pasted lines in `0.5-installed-terminal.png` |
| B2 GTK (zenity entry) -> terminal and terminal -> GTK | pass | "g:GTKCOPY99" pasted; zenity returned the terminal selection |
| B2 Firefox <-> terminal | not tested | |
| B3 USB notification, Open, write as user, Safely remove, pull without remove | pass (see notes) | `0.5-installed-usb-notification.png`; `/Mount/Media` empty afterwards |
| B4 modinfo 8852au (2357:013f), modprobe, udev rule, usb_modeswitch in PATH, gobonet_backend setuid | pass | alias `usb:v2357p013F...`; module loaded; rule link; `/usr/bin/usb_modeswitch` for lab; `-rwsr-xr-x` |
| B5 ONLYOFFICE from search, new document, save .docx, open .docx from PCManFM | pass | `0.5-installed-onlyoffice.png`; file is "Microsoft Word 2007+" with the typed text |
| B6 `apt update` hint, `sudo Compile` found | pass | hint text; `sudo Compile --help` prints usage |
| C BIOS, answers file, `--autologin --swap 1024` | pass | desktop at boot; `/Data/Variable/swap` 1 GB active; summary "automatic login to the desktop ..."; closing line "The desktop starts by itself" |
| D BIOS `--text-login` | pass | no LXDM, no inittab line; tty1 login starts X; USB mounted + notification; Log out -> tty1 prompt, stick unmounted, only PulseAudio left (exits by itself) |

Notes from testing (not fixed):
- **USB notification button order is random** (Awesome 4.3's naughty lays out `actions` with `pairs()`):
  sometimes "Open" is first, sometimes "Safely remove". In one run a click meant for "Open" hit "Safely remove".
  Fix idea for 0.6: keep only "Safely remove" as an action (clicking the notification already opens the drive).
- Once, clicking "Open" in the notification opened no window (PCManFM had just been closed; possibly its
  single-instance hand-off). The taskbar drive menu's "Open" and a later notification "Open" worked.
- The hint only appears when the unknown command is the first word of the line (`clear; apt update` shows only
  zsh's message): upstream's CommandNotFound hook looks at the first word only.
- The live session brings up no network by itself (interface `enp0s3` there; the installed system uses `eth0`).
  `dhcpcd -b` fixes it. Matters only for live-session use (e.g. Wi-Fi before installing).
- Lab: a hot-plugged `usbstick.vdi` gets a fresh differencing image on every attach (the base has a snapshot
  child), so files written during one plug are gone at the next; not a spin bug.

### Lab lessons (0.5)
- Restoring `iso-build-env-5` throws away anything changed in the build VM since; re-apply changes or (better)
  make `build-iso.sh` fetch them from the host, as was done for the LXDM theme.
- Before simulated typing, check that the search window really holds the keyboard:
  `vm/lua.sh 'return tostring(keygrabber.isrunning())'`.
- The installed system's sshd is not started at boot: tty2 root login + `lab-ssh.sh` after every boot.
- `su - lab -c ...` from the ssh root shell asks for a password here; `su lab -c ...` works.
- VM boot order is now DVD first (`--boot1 dvd --boot2 disk`).

VM snapshots now: `not even installed`, `iso-build-env-2`, `iso-build-env-3`, `iso-build-env-4`,
`iso-0.4-installed-efi`, `iso-build-env-5` (build env for 0.5), **`iso-0.5-installed-efi`** (current, powered
off: UEFI default install of the final 0.5 ISO, user lab, LXDM, layout pl, timezone UTC).

Next: the user tries ISO 0.5 on the real PC, Wi-Fi adapter first (`dist/README.md`).

## 0.6 desktop half: real-PC feedback on 0.5 fixed in the look and build VM (2026-11-14)

ISO 0.6 **not built** (a second worker still does the file-manager half). Build VM state: snapshot
**`iso-build-env-6a`** (= `iso-build-env-5` + CopyQ 6.4.0, USB-ModeSwitch rebuilt with `gobo-wifi-switch`
and the new udev rule, the sudoers rule in the build VM, the 0.6 look for `lab`). `spin/build-iso.sh`:
VERSION=0.6, copies CopyQ, writes the sudoers rule into the rootfs; `vm/serve/build-iso.sh` identical.

| # | Item | State | What changed |
|---|---|---|---|
| 1 | Keyboard input gets stuck | done | `spin/popups.lua` (new): one registry of popups, `close_all()` before every show, a click-catching backdrop for every awful.menu, Win+Escape safety net (also inside grabs); `launcher.lua` stops exactly its prompt grabber; `alttab.lua` on awful.keygrabber with a robust end; hotkeys popup closes on a click outside |
| 2 | Wi-Fi adapter does not switch by itself | done (needs the real PC) | `spin/gobo-wifi-switch` wrapper (detached, retries, log), two udev triggers, desktop trigger via sudo; see `docs/wifi-notes.md` (0.6 section) |
| 3 | Network icon always full | done | `spin/network.lua`: own cairo icons (off, no-adapter off, connecting, wired, Wi-Fi 4 levels), real state every 4 s and on click; GoboNet's widget runs hidden for its menu |
| 4 | Virtual desktops | done | `spin/desktops.lua`: 1 desktop per screen, Win+Shift+Tab list (add/remove/switch), indicator hidden with one desktop, count + window placement survive restarts |
| 5 | Screenshots | done | `spin/screenshot.lua`: Win+Shift+S card (Area/Window/Whole screen), Print = screen; ImageMagick `import` (on the image), `~/Pictures/Screenshots`, clipboard, notification -> folder |
| 6 | Clipboard history | done | CopyQ 6.4.0 (Qt 5, X11-only build), 20 items, no tray; `spin/cliphist.lua` popup on Win+Shift+V; a CopyQ script keeps the clipboard after its program closes |
| 7 | Default folders | done | `apply.sh` creates Documents, Downloads, Music, Pictures(/Screenshots), Videos + `~/.config/user-dirs.dirs`; installer chowns them |
| 8 | USB notification | done | only one action button ("Safely remove"); body click opens the drive |

### Item 1: what was actually broken (reproduced with `vm/input-test.sh`)

- **The category menu (and every other awful.menu: window menu, network list, USB menu, taskbar window
  list) holds the keyboard grab for as long as it is open, and nothing closed it on a click elsewhere.**
  A click on a window gave that window the focus (cursor blinking) but every key still went to the
  invisible-to-the-user menu grab. 0.5 baseline: 7 of 23 scenarios failed, all of them menus
  (menu + click on window / desktop / taskbar, taskbar right-click list, network menu, USB menu,
  window menu). This matches the second report exactly.
- **Latent, matches the first report:** `launcher.hide()` called `awful.keygrabber.stop()` without an
  argument. In Awesome 4.3 that removes the *oldest* grabber on the stack (`grabbers[#grabbers]`), not
  the newest. With the category menu open and the search opened over it (right click on the dots),
  closing the search removed the menu's grabber and left the hidden search prompt holding the keyboard
  (stack check: 1 grabber left, menu visible, C grab still running).
- alt-tab used the bare C keygrabber and ended only on the release of `Alt_L`; now awful.keygrabber,
  any Alt release, or any key without Alt held, and cancellable.
- The hotkeys popup closed only on a key or a click on itself (its grab stayed after a click elsewhere).
- Not a bug (lab artefact): keys sent with `root.fake_input` sometimes reached urxvt as the previous
  shortcut's letter; with VirtualBox's virtual keyboard this never happened, so the test uses that.

After the fix the regression test passes all 32 scenarios (incl. desktops, screenshot and clipboard popups), and Win+Escape inside an open menu
closes it and frees the keyboard (3 visible wiboxes -> 1, grab running -> not).

`vm/input-test.sh [scenario...]` (+ `vm/input-test.lua`): needs SSH and a running desktop; mouse through
`root.fake_input`, keys through `VBoxManage keyboardputscancode/keyboardputstring`; each scenario ends by
clicking the terminal and typing `touch /tmp/kb-<name>`. `rc.lua` exposes `spin_debug` (taskbar widgets)
for it.

### Wiring for the ISO build (0.6)

- `spin/build-programs.sh copyq` (new) and `usb-modeswitch` (again: installs `gobo-wifi-switch` fetched
  from the host as `vm/serve/gobo-wifi-switch`, writes the new rule). Tarballs `spin/programs/CopyQ--6.4.0--x86_64.tgz`
  (3.2 MB; 9.1 MB installed) and `USB-ModeSwitch--2.6.1--x86_64.tgz` (re-packed, 33 KB / 136 KB).
- Sudoers: `%users ALL=(root) NOPASSWD: /System/Index/bin/gobo-wifi-switch --session` is added to the
  **rootfs** by `build-iso.sh` (the installer copies `/Programs`, so installed systems have it; the live
  user is root). The udev rule ships inside USB-ModeSwitch (linked by SymlinkProgram into
  `/System/Index/lib/udev/rules.d` = `/usr/lib/udev/rules.d`, which Eudev reads).
- Look: `apply.sh` copies `copyq/copyq.conf` and `copyq/copyq-commands.ini` (if absent) and creates the
  folders; `xinitrc` starts `copyq`. Run on the skeleton by build-iso, so live and new users get it.
- CopyQ build notes: Qt 5.14 was built for prefix `/usr`, so its cmake files want `/usr/mkspecs`,
  `/usr/plugins/...`: the step makes temporary links. CopyQ 6.x (and 4.1/5.0) always build a Wayland
  clipboard needing extra-cmake-modules + Wayland + QtWaylandClient (none on the image): the step removes
  that part with sed (used only off X11). `copyq eval` unescapes its arguments (`'\n'` breaks scripts).

### New keys (all in the hotkeys help, Win+S)

Win+Escape close all popups / free the keyboard (was "previous desktop"); Win+Shift+Tab desktops list;
Win+, / Win+. previous/next desktop; Win+1..9, Win+Shift+1..9 (move window), Win+Ctrl(+Shift)+1..9;
Print whole screen; Win+Shift+S screenshot card; Win+Shift+V clipboard history.

### Not verified (needs the real PC)

The Wi-Fi switch with the actual adapter (only emulated with the virtual stick, see wifi-notes); Wi-Fi
signal levels (only unit-tested: `network.level_from` with sample `/proc/net/wireless` / iwconfig text);
the connecting animation during a real Wi-Fi association; screenshots on NVIDIA with picom (VM: vmwgfx,
works); a physical second monitor (fake screens only); CopyQ with images from Firefox/GTK apps (tested:
terminal text, screenshot image, GTK not); real typing habits (only simulated input).

Screenshots: `docs/screenshots/0.6-*` (hotkeys help, desktops dark/light, screenshot card dark/light, area selection,
saved notification, clipboard history light, network icons dark+light strip, USB notification with one
button, Wi-Fi switch from the session).

Lab lessons (0.6):
- The X session can be started without typing a login: `openvt -f -c 7 -s -- su lab -c "... exec zsh -i -l -c startx"`
  (`-i` is needed: the environment cache, LUA_PATH, QT_PLUGIN_PATH come from the interactive zshrc).
- `VBoxManage controlvm ... setlinkstate1 off` also cuts the SSH port forward (same NIC): take screenshots.
- `vm/lua.sh` output passes through `tail -n 2`: write longer results to a file and `cat` it.

VM snapshots now: ..., `iso-build-env-5`, `iso-0.5-installed-efi`, **`iso-build-env-6a`** (current; taken
powered off, VM started again headless; the lab X session is started with the openvt line above).

## 0.6 file-manager half (2026-11-14)

ISO 0.6 **not built**. Build VM state: snapshot **`iso-build-env-6b`** (= `iso-build-env-6a` + LibFM/PCManFM
rebuilt with the 0.6 patches, GoboFiles 0.6, USB-ModeSwitch with the final `gobo-wifi-switch`, the 0.6 look for
`lab`). `spin/build-iso.sh` names `iso-build-env-6b`, copies GoboFiles and checks its files; the `vm/serve/`
copies of `build-iso.sh`, `build-programs.sh`, `gobo-wifi-switch` are identical to `spin/`.
New files served for builds: `vm/serve/libfm-1.2.5-gobo.patch`, `vm/serve/pcmanfm-1.2.5-gobo.patch` (copies
of `spin/patches/`), `vm/serve/gobofiles.tgz` (`cd spin && tar czf ../vm/serve/gobofiles.tgz gobofiles`).
Tarballs re-packed/added in `spin/programs/`: LibFM, PCManFM, GoboFiles, USB-ModeSwitch.

| # | Item | State | What changed |
|---|---|---|---|
| 0 | `gobo-wifi-switch` lock in /var/run | done | installed in the build VM; `/var/run` (= `/Data/Variable/run`) is a root-owned 755 tmpfs; `sudo -n ... --session` as `lab` logs "nothing to do"; tarball re-packed |
| 1 | File search | done | the built-in search worked (Tools -> Find Files, `search://`) but needed wildcards: typing `report` found only a file named exactly "report", and there was no button. New: **Ctrl+F** / magnifier button right of the location bar / Tools -> Search...: one name field (plain text = "name contains", not case sensitive, `*`/`?` used as typed), "Only in this folder (X)" or "In this folder and all folders inside it" (last choice remembered while PCManFM runs); results in a "Search Results" tab, they open like normal files. Old dialog: Tools -> Advanced Search (Ctrl+Shift+F) |
| 2 | "USB drives" entry | done (+ bonus) | fixed side-pane entry from the spin's LibFM: last of the places (above the separator), Papirus' blue USB icon, user bookmarks always below it; each mounted stick listed under it (drive icon), updated on plug/unplug (watches `/Mount/Media`). `apply.sh` removes the 0.5 bookmark line |
| 3 | Desktop icons | done | Awesome starts `pcmanfm --desktop` (`awesome/spin/desktop_icons.lua`); details below |
| 4 | Trash | done | Delete in PCManFM -> `~/.local/share/Trash` (GLib does this without gvfs); Trash icon on the desktop opens `gobo-trash` (restore, delete for good, empty, age 1/3/6 months, default 6); `gobo-trash-purge --auto` 20 s after Awesome starts and every 24 h; files on USB sticks / other disks: asked (default "No"), then deleted for good |
| 5 | Folder colours | done | right click on a folder under home -> "Folder colour..." -> GTK colour chooser (zenity) with palette, custom colour and "Default"; shown in PCManFM and on the desktop, survives restarts and moves |

### How it works

- **Patches** (`spin/patches/`, applied by `spin/build-programs.sh libfm` / `pcmanfm`):
  - LibFM: `fm-places-model.c` (USB entries), `fm-file-info.c` (a folder's icon from `<folder>/.directory`,
    `[Desktop Entry] Icon=`), `fm-file-ops-job-delete.c` (only files on the home folder's file system are trashed;
    the stock check used `g_mount_can_unmount`, which tells nothing without gvfs), `fm-progress-dlg.c` (clear
    question, default No). Custom actions are compiled in again (the release tarball carries Vala's C output).
  - PCManFM: `main-win*.c` (search dialog, button, Ctrl+F), `desktop.c` (right click on an empty desktop spot
    runs `$GOBO_DESKTOP_MENU_COMMAND`; Ctrl+right click = PCManFM's own desktop menu; the icon area reads
    `_NET_WORKAREA` directly).
- **Desktop** (`look/gobo11/awesome/spin/desktop_icons.lua`, started from `rc.lua`): 1.5 s after Awesome starts it
  saves the drawn wallpaper (`root.wallpaper()`, all screens) to `~/.cache/gobo11/desktop-wallpaper-<mode>-WxH.png`,
  writes the `[*]` group of `~/.config/pcmanfm/default/desktop-items-N.conf` (wallpaper mode "screen"; text white
  with black shadow in dark, `#1b2230` with a light shadow in light; Inter 10; no PCManFM trash/mount icons; icon
  positions saved in that file are kept) and starts the desktop, or switches it off and on when the settings
  changed. The power menu's light/dark switch restarts Awesome, so picture and colours follow (checked both ways).
  Awesome 4.3 publishes no `_NET_WORKAREA`; the module sets it with `xprop` (full width, down to the taskbar top,
  16 copies), also on workarea changes, so icons stay above the taskbar. A rule makes the desktop window sticky,
  `below`, not in the taskbar and **not focusable**. Same path for `startx` and LXDM (both run `~/.xinitrc` ->
  Awesome); `xinitrc` itself is unchanged.
- **Menus on the desktop (decision)**: right click on an empty spot = Awesome's menu as before (PCManFM's forwarded
  click never reached Awesome, whose root bindings are passive grabs; hence the command
  `awesome-client 'spin_desktop_menu()'` passed in the environment); right click on an icon = PCManFM's file menu
  (Open, Cut/Copy, Move to Trash, Rename, Folder colour..., Properties); Ctrl+right click on an empty spot =
  PCManFM's desktop menu (Create New, Paste, Sort, Desktop Preferences). A left click elsewhere closes Awesome's menu.
- **Trash**: `spin/gobofiles/gobo-trash.c` (window), `gobo-trash-purge` (all deleting; refuses a HOME that is not
  absolute, a trash path not ending in `/Trash`, item names that are empty, `.`, `..` or contain `/`; `cd /` first,
  because `find` gives up in an unreadable working directory - found by the fixture test). Age in
  `~/.config/gobo-trash.conf`, log in `~/.cache/gobo-trash.log`. Desktop icon `~/Desktop/Trash.desktop` written
  once by `apply.sh` (marker `~/.config/gobo11-trash-icon`, so a deleted icon stays deleted). Also in the
  application search as "Trash".
- **Folder colours**: `gobo-folder-colour` recolours Papirus' 64 px folder SVG into
  `~/.local/share/gobo-folder-colours/folder-rrggbb.svg` (back part 82 % of the colour, like Papirus) and edits only
  the `Icon=` line of `[Desktop Entry]` in the folder's `.directory` (other groups kept; Default removes the line,
  and the file when nothing else is left), then `touch`es the folder so open views update. The menu entry is hidden
  for folders outside home (`ShowIfTrue=gobo-folder-colour --check %f`) and the script refuses them as well.
- Installer: only a comment changed; `~/Desktop/Trash.desktop` and `~/.config/gobo11-trash-icon` are inside the
  folders it already chowns, the other new files are created by the user's own session.

### Verified in the VM (simulated mouse/keys, user lab, dark and light)

- Search: Ctrl+F dialog, a plain word finds 3 files incl. sub-sub-folders, "only this folder" mode, tab title.
- USB: entry order with two bookmarks; stick entry disappears/appears on detach/attach of the virtual stick.
- Trash: Delete -> confirm -> file in Trash with `.trashinfo`; delete on the stick -> our question, file gone, no
  `.Trash-1000` on the stick; Trash window lists name / original folder / date, Restore puts the file back,
  Delete for good and Empty Trash (both confirmed), the age switch writes the config.
- Purge fixtures (`vm/serve/trash-fixture-test.sh`, throwaway HOME): items 8/5/2 months and 2 weeks old, a
  7-month folder with a read-only sub-folder and a link to an outside folder, a link to an outside file, a name
  `old -rf *`, bad and missing dates: 6 months removes exactly the 4 old ones, then 3 months the 5-month one,
  1 month the 2-month one; bad/missing dates kept; invalid names refused; empty and relative HOME refused;
  outside files kept.
- Folder colours: menu entry, chooser, green applied live, Default, `.directory` with a `[File Manager]` group
  kept, `/tmp` refused, coloured folder on the desktop.
- Desktop: icons of `~/Desktop` (new files appear at once), wallpaper identical to Awesome's, light/dark switch,
  icons above the taskbar with 17 files, Awesome menu on right click (also after a mode switch), Ctrl+right click,
  double click on Trash, Awesome restart and `vm/push-look.sh`.
- Keyboard-focus regression `vm/input-test.sh` with the desktop running: **32 of 32 pass** (incl. menu + click on
  the desktop, right click on the desktop; the keyboard always ends in the terminal).

### Not verified (needs the real PC or an install)

The LXDM login path with the desktop (same `~/.xinitrc` -> Awesome, so expected to work; only the lab's
`startx` session was used); NVIDIA + picom with the desktop window; a physical second monitor (the picture spans
all screens, settings are written for each); exFAT/NTFS sticks with the trash rule; the 24-hour purge timer
(only the start-up run and the script itself).

### Known limits / decisions to review

- The desktop window is not focusable: Delete, F2 and arrow keys do nothing on desktop icons; the mouse menus work.
- "Desktop Preferences" (Ctrl+right click) can set another wallpaper, but the next Awesome start (or light/dark
  switch) puts ours back.
- File manager windows run inside the desktop's PCManFM process (single instance, as in LXDE).
- Delete on a USB stick asks twice (PCManFM's own "move to trash?" first, then ours).
- Trash folders on other disks/sticks (`.Trash-1000`, made by other systems) are not shown.
- Search: a comma in the text splits it into two patterns (libfm's search syntax).
- Not from this work, found while testing: opening a plain text file (from search results or any folder) shows
  an empty "Choose Application" list. The image has no `update-desktop-database` (desktop-file-utils), so no
  `mimeinfo.cache`, and no default for text/plain; only the types in `~/.config/mimeapps.list` (OnlyOffice) open
  directly. gvim declares text/plain; a GUI text editor default is the owner's choice. Folders and office files
  from search results open normally.

Downloads: none in this half (everything built from the sources already in `/Data/Build/src3`).
Size: LibFM tgz 864 -> 888 KB, PCManFM 418 -> 420 KB, GoboFiles 17 KB tgz / 96 KB installed.
Screenshots: `docs/screenshots/0.6-search-dark.png`, `0.6-search-results-dark.png`, `0.6-usb-sidepane-dark.png`,
`0.6-desktop-icons-light.png`, `0.6-desktop-menu-dark.png`, `0.6-trash-dark.png`, `0.6-folder-colour-dark.png`,
`0.6-folder-colour-chooser-dark.png`.

Lab lessons (0.6 file-manager half):
- Awesome's root-window bindings are passive grabs: events sent with XSendEvent to the root never reach them.
- GTK 3.24 here reported no work area even with `_NET_WORKAREA` and `_NET_SUPPORTED` set (GDK's EWMH check
  failed in a test program); PCManFM's GTK 2 code path that reads the property directly works.
- `su lab -c` from the ssh root shell runs in `/Users/root` (unreadable for lab): `find` aborts before `-exec`.
- `pkill -9 -u lab pcmanfm` before rebuilding LibFM/PCManFM (the desktop process keeps the old libraries).
- xsecurelock had locked the idle lab desktop once more (black screenshot): `pkill xsecurelock`, `xset s off`.

VM snapshots now: ..., `iso-build-env-6a`, **`iso-build-env-6b`** (current; taken powered off, VM started again
headless; the lab X session is started with the openvt line of the 0.6 desktop half).

## ISO 0.6 built and install-tested in the VM (2026-11-14)

**`dist/GoboRefined-0.6.iso`**, 2,863,726,592 bytes, sha256 `0f01edeb327f476213a2ac9b26a5bfde78e3b2e2af639fce148461216e19bdf1` (`.sha256` next to it; matches the
build VM's `sha256sum`). `dist/GoboRefined-0.5.iso` is kept. Built from snapshot `iso-build-env-6b` with
`spin/build-iso.sh`. Two builds: the first (sha256 `28158cd0...`, 2,863,726,592 bytes) was tested, three bugs were
found and fixed (below), and the ISO was rebuilt from a fresh restore of `iso-build-env-6b`; the first build's file
in `dist/` was overwritten by the second.

### Fixed during the test (all small, in the repo)

| # | Bug | Cause | Fix |
|---|---|---|---|
| 1 | Installed systems had **no** `%users ... gobo-wifi-switch --session` sudo rule: `sudo -n` asked lab for a password, so the desktop's Wi-Fi switch trigger could not run (the udev trigger runs as root and was not affected) | `ProfileInstall` (used by `gobo-install`) replaces every program's `Settings` with `Current/Resources/Defaults/Settings`; build-iso had written only `Sudo/Settings/sudoers` (the live session runs as root; the 6a/6b workers tested in the build VM) | `spin/build-iso.sh` appends the rule to both copies and runs `visudo -c -f` on each |
| 2 | Window menu (right click on a title bar) + click on a terminal: the **keyboard went to the desktop window** (input test `window-menu` failed 3 of 3 runs on the installed system) | `popups.client_at()` walks `client.get(nil, true)`; the PCManFM desktop window (type desktop, not focusable) was returned for a point inside the terminal, so the backdrop click focused it (focus trace: `popups.lua:53`) | `look/gobo11/awesome/spin/popups.lua`: `client_at` skips `type == "desktop"` and non-focusable clients |
| 3 | On desktop 2, **Move to Trash on a desktop icon**: the Confirm dialog opened on desktop 1 (taskbar marked 1 urgent), invisible | the dialog is transient for the desktop window; Awesome's `ewmh.tag` gives a transient window its parent's tags, and the sticky desktop window's own tag is desktop 1 | `look/gobo11/awesome/rc.lua`: rule callback puts windows transient for the desktop window on the screen's selected desktop |

Fixes 2 and 3 were checked on the first build's UEFI install after `vm/push-look.sh` (window-menu PASS twice;
the Confirm dialog appeared on desktop 2), then again on the final ISO.

### Tests (VM; keyboard through VirtualBox, mouse through `root.fake_input`)

Final ISO (after a fresh restore of `iso-build-env-6b`): all three installs pass again.
- (b) BIOS `--answers --autologin --swap 1024`: desktop at boot, 1 GB swap; as lab
  `sudo -n /System/Index/bin/gobo-wifi-switch --session` runs without a password (log: "no adapter in CD mode ...
  nothing to do"), `sudo -n true` and `... --udev` are refused (fix 1).
- (c) BIOS `--answers --text-login`: tty1 login starts the desktop.
- (a) UEFI, typed answers (lab, Europe/Warsaw, pl): GRUB entries, greeter, LXDM login; `gobo-trash-purge --auto`
  removed a planted 8.5-month-old item about 20 s after login; the seven folders belong to lab; the sudo rule as in
  (b); `modprobe 8852au`; udev rule link; efibootmgr entry "GoboLinux"; **`vm/input-test.sh` 32 of 32** (fix 2);
  from desktop 2, Move to Trash on a desktop icon opens Confirm on desktop 2 (fix 3). This install is the snapshot
  `iso-0.6-installed-efi`.
The GUI checks in the table below were not all repeated on the final ISO; the image differs from the first build
only in the sudoers rule and the two look files, which the table's GUI checks already ran with.

Checks on the **first** build (identical except the three fixes; the GUI checks of install (a) were made after
pushing the fixed look):

| Check | Result | How |
|---|---|---|
| ISO boots (BIOS and UEFI), welcome text GoboRefined | pass | screenshots; `/sys/firmware/efi` present in the UEFI live session |
| GRUB "GoboRefined 0.6 (GoboLinux 017.01)" + safe graphics | pass | BIOS and UEFI screenshots |
| (a) UEFI, typed answers (lab, Europe/Warsaw, pl), LXDM login | pass | summary + greeter screenshots; desktop after typed login |
| (b) BIOS `--answers --autologin --swap 1024` | pass | desktop at boot; `swapon -s` 1 GB; Log out -> greeter |
| (c) BIOS `--answers --text-login` | pass | tty1 login -> desktop; no LXDM in inittab or process list; Log out -> tty1 prompt |
| Live session (root): desktop icons, Trash (delete/restore), Ctrl+F, USB drives + stick | pass | screenshots `0.6-iso-live-*` |
| `vm/input-test.sh` on (a) | 31/32 (window-menu) -> fix 2 -> window-menu PASS | log |
| Title-bar double click max/restore | pass | 720x432 -> 1280x752 maximized -> 720x432 |
| Terminal select = copy, right click paste | pass | xclip PRIMARY+CLIPBOARD "copyword42"; pasted at the prompt |
| USB: unplug/replug virtual stick -> automount, notification (one button), click opens PCManFM | pass | mount list; screenshots |
| ONLYOFFICE starts / PaVuControl from volume icon / Displays... (menu) opens LxRandr | pass | client classes; screenshot |
| Lock (Win+L) + unlock with password | pass | xsecurelock running -> gone after typing |
| Light/dark switch | pass | screenshot; `beautiful.mode` back to dark |
| Log out + log in again (LXDM) | pass | greeter, login as second, then lab again |
| `apt update` hint | pass | screenshot |
| Win+Shift+Tab: 1 desktop at first, add (2, 3), remove (back to 2), still 2 after re-login | pass | `#screen.primary.tags`; `~/.cache/awesome/spin-desktops` |
| Win+Shift+S: area / window / whole screen | pass | `~/Pictures/Screenshots`: 300x200, 724x436, 1280x800 |
| Win+Shift+V: text pick pastes; picture pick puts image/png on the clipboard | pass | terminal + `xclip -t TARGETS` |
| Win+Escape | pass | input-test scenarios panic-in-menu, desktops-escape, shot-escape |
| Network icon wired -> `setlinkstate1 off` -> on | pass | `0.6-iso-network-wired-off-wired.png` (dim icon with red cross while off) |
| Default folders exist, owned by the user | pass | `stat`: lab:users 755 for all seven (also on (b)) |
| Ctrl+F "report" in home: all folders (3 hits incl. sub/deep, case-insensitive) and only this folder (1) | pass | screenshots; `recursive=1/0` in the search URI |
| "USB drives" below the fixed places, GOBOSTICK listed | pass | screenshot |
| File created in ~/Desktop appears on the desktop | pass | screenshot |
| Trash: delete -> restore -> empty (confirm) | pass | file system + `gobo-trash.log` "emptied the trash" |
| `gobo-trash-purge --auto` at login | pass | planted items 8.5 and 10.5 months old: removed about 20 s after each login, a 4-day-old item kept; log lines |
| Folder colour in home; refused outside | pass | green Documents icon, `.directory` Icon=...73d216.svg; `/tmp`: menu entry absent, `--check` 1, `--set` refused |
| `sudo -n .../gobo-wifi-switch --session` without password; `sudo -n true` fails | **fail** on the first build -> fix 1 (final ISO: see above) | as lab |
| udev rule where udevd reads it | pass | `/usr/lib/udev/rules.d/40-gobo-realtek-wifi.rules` -> USB-ModeSwitch (Eudev 243 reads `/usr/lib/udev/rules.d` = `/System/Index/lib/udev/rules.d`) |
| `modprobe 8852au` | pass | loaded with cfg80211; alias `usb:v2357p013F` |
| Second user (`AddUser -f "Second User" second`, password via `openssl passwd -6` + `usermod -p`) | pass, one gap | look, all folders, Trash icon, desktop after LXDM login; **its desktop keyboard layout is `us`** (skeleton `.xinitrc`), while the login screen and the installed user use `pl` |

### Findings, not fixed (decide later)

- **Second users get keyboard layout `us` on the desktop**: the installer writes the chosen layout only into
  root's and the installed user's `~/.xinitrc` and into the X config for the login screen; the skeleton keeps `us`.
- `AddUser` sets the password through `passwd`, which needs a terminal; from a script it fails ("Authentication
  token manipulation error") and the account is left without a password.
- **Plain text files open with nothing** (task item): the only text editors on the image are Vim/gvim and Nano,
  so, as instructed, no `text/plain` default was set in `look/gobo11/xdg/mimeapps.list`.
- The desktops list shows "Pcmanfm" (the desktop window) among the windows of desktop 1.
- After the light/dark switch (an Awesome restart) the view returns to desktop 1 (windows keep their desktops).
- The application search does not find LxRandr by "displays" (Menu -> Desktop -> Displays... works).
- During the test the build VM's leftover `/Data/Build/GoboLinux-017.01-spin.iso` (0.1 era) was deleted to make
  room; it still exists inside snapshot `iso-build-env-6b` (the restore for the rebuild brought it back).

### Lab lessons (0.6 ISO)

- Over ssh, `pgrep -f "gobo-install --answers"` matches the remote shell running the pgrep itself: use a bracket
  pattern (`gobo-[i]nstall`) when waiting for the installer to exit.
- After a BIOS install (MBR, no ESP) the UEFI firmware boots the DVD without any clean-up; the efibootmgr/ESP
  clean-up from the 0.4 notes is only needed when the disk still holds a UEFI install.
- No ImageMagick on the host: crop screenshots with PowerShell's `System.Drawing`.
- `setlinkstate1 off` cuts SSH; take screenshots and turn the link back on before the next ssh command.
- Restoring `iso-build-env-6b` for the rebuild discards the test install; the install tests are then redone.

VM snapshots now: ..., `iso-build-env-6a`, `iso-build-env-6b` (build env for 0.6), **`iso-0.6-installed-efi`**
(current, powered off: UEFI install of the final 0.6 ISO, typed answers, user lab, LXDM, layout pl,
Europe/Warsaw).

Next: the user tries ISO 0.6 on the real PC, Wi-Fi adapter first (`dist/README.md`).
