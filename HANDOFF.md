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
