# Handoff

Updated 2026-11-15. The spin is now called **GoboRefined** (an unofficial spin of GoboLinux 017.01); current: **0.8 release candidate (A/B system, installer menus)**, `dist/GoboRefined-0.8.iso` + `GoboRefined-0.8.update` (see the last section; 0.5, 0.6 and the 0.8 dev builds kept). Direction: **modernized spin, path of least resistance** (see `docs/goals.md`).

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

## 0.8: A/B system (two system slots + data partition) — built and tested in the VM (2026-11-14)

Specification: `docs/ab-design.md` (corrected where reality differs; deviations below). ISOs
**`dist/GoboRefined-0.8-dev1.iso`** (sha256 `5ebd9d6f...`) and **`-dev2.iso`** (`d5e07efb...`), each 2,867,200,000
bytes, with **`GoboRefined-0.8-dev1.update`** (`bcec6e74...`) and **`-dev2.update`** (`fd10f726...`), each
2,734,067,712 bytes; `.sha256` files next to them. dev2 = dev1 + the lab test variant (`vm/serve/ab-test-variant.sh`:
new program HelloAB, one changed line in CoreUtils' Description). 0.5 and 0.6 ISOs kept. `dist/*.update` is gitignored.

### How it works

- **Disk (GPT):** `BIOSBOOT` 1 MiB, `GOBO_BOOT` 512 MiB FAT32 (ESP; GRUB, `grub.cfg`, `grubenv`), `GOBO_A` 12 GiB,
  `GOBO_B` 12 GiB, `GOBO_DATA` rest. GPT names = file system labels. Disks under 32,000,000,000 bytes are refused.
- **Root** (`spin/ab/dracut/90goboab/`, dracut module `goboab`, active only with `root=gobo`): the data partition is
  checked (`e2fsck -p`) and mounted, the slot read-only, overlay
  `lowerdir=System-Overlay/install:slot, upperdir=System-Overlay/upper` (or a tmpfs upper for "without my system
  changes", with the current account files copied in); `/Users` and `/Data/Variable` bind-mounted from the data
  partition; the data partition is moved to `/System/Data`, the slot to `/System/Slot`. A slot without
  `/gobo-slot.env` refuses to boot. The initramfs also performs a requested reset (`upper` -> `previous-upper`,
  accounts kept) and, on a version change, removes the files listed in `share/gobo-update/generated-caches` from both
  overlay layers and `/Data/Variable`, then writes `System-Overlay/first-boot-pending`. The initramfs is built by
  `build-iso.sh` (`dracut --no-hostonly -L 4 --add goboab`; same module set as the stock image, which was built with
  plain `dracut --kver 6.12.16-Gobo`; the module directory lives in GoboSpin and is linked into Dracut's `modules.d`).
  The live ISO keeps its own stock initramfs (isolinux/efiboot are replayed unchanged).
- **`gobo-make-system SOURCE TARGET`** (GoboSpin bin): mounts the live squashfs with a tmpfs layer, runs upstream
  `ProfileInstall` *inside the image* into TARGET, then applies the generic settings (wired DHCP, boot task line in
  BootUp, locale, inittab link, resolv.conf, power sudo rule, mount points, `System/Kernel/Boot/initramfs` link).
  Used by gobo-install for slot A and by build-iso for the update, so both are the same tree.
- **Installer:** partitions, formats (GPT names checked, never a mounted device or the running root), slot A via
  gobo-make-system, writes `gobo-slot.env`, copies the slot's `/Users` and `/Data/Variable` to the data partition,
  assembles the target as the initramfs would but with **`System-Overlay/install`** as the writable layer; the old
  configuration steps then run unchanged (accounts, hostname, fstab without "/", swap file, time zone, look,
  LXDM/text login). GRUB: EFI image via grub-mkimage (finds GOBO_BOOT by UUID) + efibootmgr entry; BIOS via
  `grub-install --boot-directory=<GOBO_BOOT>` into the BIOS boot partition (worked first time). `--source IMAGE`
  (development) installs from another squashfs or an unpacked tree and allows running outside the live session (used
  for the prototype on a spare disk). Question flow unchanged; no `dialog`.
- **GRUB menu** (static `grub.cfg` on GOBO_BOOT; UUIDs/PARTUUIDs as `set gobo_*` lines that gobo-update also reads):
  per filled slot: normal, "without my system changes", "safe graphics"; an empty slot is listed as "Slot B: empty"
  and only prints a message. grubenv: `slot`, `try_slot`, `tries_left`, `rollback_from`. Try boots get
  `rd.shell=0 rd.emergency=reboot panic=10` and GRUB's `fallback` (old slot). Screenshot `0.8-boot-menu.png`.
- **`gobo-update`**: `FILE`, `--status`, `--rollback`, `--reset-system-changes`, `--yes`, internal `--boot-task`.
  Update file = squashfs + 8 KiB trailer (manifest + RSA-3072 signature, base64). Checks: signature, size, sha256;
  target slot found by PARTUUID, GPT name `GOBO_X` checked, not mounted anywhere, not the running slot (UUID and
  `/System/Slot`), same disk; formatted with the slot's old file system UUID; `gobo-slot.env` written last; grubenv
  changed by copy + rename. `--boot-task` (end of BootUp): first start of a new version (ldconfig; the other caches
  only when the user added programs; new `/Data/Variable` folders; `apply.sh` for every home as its owner), then
  marks the slot good or turns a rollback into `/Data/Variable/lib/gobo-update/notice`. Log:
  `/Data/Variable/log/gobo-update.log`. Screenshot `0.8-status.png`.
- **Desktop:** `look/gobo11/awesome/spin/updates.lua` shows "System updated" / "System update undone" once per user.
  `apply.sh` now keeps the user's light/dark choice (it used to reset GTK to dark) and writes
  `~/.config/awesome/look-version`. Still overwritten by apply.sh, as before: `~/.config/awesome/*`, `picom.conf`,
  `fonts.conf`, `.xinitrc` (layout kept), the gobo11 block of `.Xresources`.
- **Internal partitions:** udev rule `80-gobo-internal.rules` (GoboSpin) sets `UDISKS_SYSTEM_INTERNAL=1` (+ IGNORE,
  NOPOLICY) for `GOBO_*` by GPT name or label, so udevil refuses them for users; `xinitrc` starts devmon with
  `--ignore-label` for all four. The "USB drives" place only lists what is mounted under `/Mount/Media`, so it never
  shows them (libfm itself was not changed).
- **Signing key:** public `spin/ab/update-signing.pub.pem` (in the image); private `vm/keys/update-signing.pem`
  (gitignored, never printed). For a build it is piped into the build VM's RAM (`/dev/shm`); build-iso deletes it.

### Build

Snapshot **`iso-build-env-8a`** (= 6b + one build run; `/Data/Build/work3` and `Recipes-git` were deleted for
space; the stock ISO must be attached as `/dev/sr0`). Refresh `vm/serve/ab.tgz` (`cd spin && tar czf
../vm/serve/ab.tgz ab`), `gobo11.tgz` and the `build-iso.sh` copy, put the key into RAM
(`vm/ssh.sh 'umask 077; cat > /dev/shm/gobo-update-signing.pem' < vm/keys/update-signing.pem`), then in the VM
`VERSION=0.8-devN nohup bash /Data/Build/build-iso.sh > /Data/Build/build.log 2>&1 &` (~22 min; peak ~12 GB in
/Data/Build: copy ISO + update to the host and delete them in the VM before the next build). Default in the file:
`VERSION=0.8-dev2`.

### Tests (VM)

| Test plan point | UEFI | BIOS | How verified |
|---|---|---|---|
| 1 install, boot, login, 0.6 checks | pass | pass (`--autologin --swap 1024`) | install 83 s / 77 s from the ISO; greeter login (UEFI) / autologin (BIOS) to the desktop; `vm/input-test.sh` 32/32 on both; USB stick automounted with notification; GOBO_* never mounted (also with a second GoboRefined disk attached); swap file on the data partition active |
| 2 persistence | pass | (part of 3) | `vm/serve/ab-persist-test.sh`: user `second`, a line in `/System/Settings/hosts`, hand-installed `/Programs/TinyAB` with a shared library (`SymlinkProgram`, `ldconfig`) — all there after reboot |
| 3 update dev1 -> dev2 | pass | pass | `gobo-update` 37-38 s; after reboot slot B 0.8-dev2 default; point-2 changes intact; `hello-ab` (new program) and the CoreUtils line visible; ld.so.cache regenerated with libtinyab; `look-version` 0.8-dev2 in every home; light mode kept; "System updated" notification (`0.8-updated-notification.png`) |
| 4 rollback by hand | pass | pass | `--rollback` -> A (dev1), again -> B |
| 4 automatic rollback | pass | pass | new slot's init overwritten: kernel panic "Attempted to kill init", reboot after 10 s, twice, then GRUB starts the old slot; notice + red "System update undone" (`0.8-rollback-notification.png`); `--status` shows "last rollback" |
| 5 without my system changes | pass | not tested | inittab in the overlay stripped of getty/LXDM: normal boot ends in "no more processes left"; "... without my system changes" boots to the login screen; `--status` says "WITHOUT system changes" (`0.8-status-safe-mode.png`); then `--reset-system-changes` + normal boot: login works, user `second` kept, hosts line and TinyAB gone, old upper in `previous-upper` |
| 6 power cut during an update | pass | not tested | VM killed while unpacking into slot A (6.3 of 8.1 GB written): slot B started normally, menu and `--status` show slot A empty; a later update into A worked |

Also seen: an update file copied into the system just before a power cut came back with zeros at its end, and
gobo-update refused it (bad signature) — the check works; `sync` after copying an update.

Final state: snapshot **`iso-0.8-dev-installed-efi`** — UEFI install of dev1 (with the repo's installer, see below),
updated to dev2: slot A 0.8-dev1, slot B 0.8-dev2 running/default. The spare prototype disk
`vm/GoboLinux-017.01/proto-ab.vdi` (35 GB dynamic, added for this work on SATA port 2) is detached but kept; it is
attached in `iso-build-env-8a`. VM firmware EFI, powered off.

### Measured

Install 76-83 s (VM). Update 37-38 s (2.6 GB file: verify ~15 s, unpack ~20 s). Update file 2.73 GB; system tree
8.1 GB (not 6.7 GB as in the design; OnlyOffice etc.) -> **3.1 GB free in a 12 GiB slot**. Data partition on the
40 GB VM disk 15.5 GiB. Overlay right after install ~200 KB; after the first update with a user program ~9.4 MB.

### Deviations from the design (why)

1. **Three layers instead of one overlay** (read-only `install` layer for install-time settings): with one overlay,
   "without my system changes" and the reset would also drop accounts/hostname/login setup — nobody could log in.
2. **"Without my system changes" copies the current account files** into the memory layer, so passwords changed
   later work. If the broken file is `passwd`/`shadow`, this entry does not help.
3. **Generic settings moved into the image** (`gobo-make-system`) so updates can change them.
4. **Caches are regenerated only when the user added programs**; otherwise removing them from the overlay is enough.
   Removal happens in the initramfs (a lower layer cannot be changed at run time).
5. **Slot completeness marker** `/gobo-slot.env` and **fixed file system UUIDs per slot** — needed for a static
   grub.cfg and for power-cut safety.
6. **"32 GB"** = 32,000,000,000 bytes; the data partition is then ~5 GB (design: 8 GB or more).
7. **Signing in the build VM with the key in RAM only**; build-iso refuses to run without it.
8. The slot is marked good at the **end of BootUp** (just before getty/LXDM start), not when the greeter is drawn.
9. `dialog` menus not added (as instructed).

### Changed after the dev2 ISO was built (in the repo, NOT in any ISO yet)

- `installer/gobo-install`, `gobo-update`: ext4 made with `-O ^orphan_file`. After power cuts the kernel logged
  "EXT4-fs error ... bad orphan inode" on the data partition (state "clean with errors"). The final install (made
  with this installer, copied over the ISO's in the live session) showed no error after one power cut — one test,
  not conclusive.
- `goboab-root.sh`: logs "data partition check: e2fsck exit N". Tested by patching slot A's initramfs on the BIOS test
  install: **e2fsck exits 0, yet the kernel still replays the journal at mount** — e2fsck in the initramfs does not
  seem to replay it. Not solved (the kernel replay works, so data was fine), but the pre-mount repair does not do
  what it is meant to.
- `gobo-update`: no bash "ignored null byte" warning on a damaged trailer.

### Fragile / not trusted yet on a real PC

- e2fsck in the initramfs (above). Slots are never fsck'd (read-only after the update completes).
- A slot holds 8.1 of 12 GiB: an image 3 GB larger will not fit (gobo-update checks and refuses).
- The update file is verified, then read again by unsquashfs: whoever can change it in between (physical access to
  the stick) could slip in other content. Copying it to the data partition first would close that.
- GRUB itself and grub.cfg are never updated by gobo-update.
- New system accounts in a future image would be hidden by the install layer's passwd.
- `/` shows the slot's `gobo-slot.env` and `lost+found` (cosmetic). `--status` needs root.
- Shutdown does not explicitly unmount the data partition (busy under the overlay); relies on the journal.
- NVMe partition names, real UEFI firmware and efibootmgr on real firmware untested; Wi-Fi etc. unchanged from 0.6.

### Lab lessons (0.8)

- `vm/vbox-keys.sh`: tty switch, typing, screenshots, and the lab passwords from `lab-answers.env` without printing
  them. Installed systems: tty2 root login + `lab-ssh2.sh` after every boot (or the lab-only sshd line in BootUp,
  which lives in the overlay and goes away with a reset).
- VirtualBox EFI: a snapshot restore can reset NVRAM boot entries; `efibootmgr -n <CD-ROM entry>` boots the ISO
  once; with a second GoboRefined disk attached the firmware may start that one instead.
- `lsinitrd ... | grep -q` under `set -o pipefail` fails (SIGPIPE): capture the list first.
- GoboLinux links are absolute (`/System/Index/bin/x -> /Programs/...`): `-x` on them from outside the tree fails.
- A stopped build-iso run can leave proc mounted inside the rootfs; build-iso now refuses to pack in that case.
- openssl on Windows writes CRLF PEM files: convert before comparing keys.

Downloads: none.

## 0.8 release candidate: hardening, installer menus, ISO 0.8 (2026-11-15)

**`dist/GoboRefined-0.8.iso`** (2,867,200,000 bytes, sha256 `d31f8c979a1dd0889f31f1e5bee028a1827306f90eb003ac34e93a5a23e8ba38`)
and **`dist/GoboRefined-0.8.update`** (2,734,075,904 bytes, sha256 `7b02b424b6a8f77759104ff87a5b1004bad4fd2f0ab93bbb03daf072ff41249b`);
`.sha256` files next to them, checked on host and build VM. One build (from `iso-build-env-8a`, VERSION=0.8).
`dist/README.md` rewritten for the owner's real-PC test.

### Hardening (A)

| # | Item | State | How verified |
|---|---|---|---|
| 1 | Slot size | done | installer: disk >= 48,000,000,000 bytes -> 16 GiB slots, else 12 GiB. gobo-update reads the slot size from the device (unchanged code, checked). 64 GiB disk -> 16/16/31.5 GiB; 40 GiB disk -> 12/12/15.5 GiB |
| 2 | Update file read twice | done | file opened once (fd 8), checked and unpacked through `/proc/self/fd/8`; must be owned by root or `$SUDO_UID` and not group/other-writable; size+mtime re-checked after unpacking. Tests: mode 666 refused, owner uid 1000 refused, a `touch` during unpacking -> "changed while it was being installed", slot left empty, symlinked path works |
| 3 | Data partition after power cuts | done | goboab-root now sends every e2fsck line to the kernel log. Finding: **e2fsck -p in the initramfs does replay the journal** ("recovering journal", clears orphan inodes) and the kernel then mounts a clean fs; same e2fsck 1.47.1 as mkfs. The old "kernel still replays" note is not reproducible (old log went to a file that was not kept). 3 forced power-offs (2 while writing files, 1 while gobo-update unpacked): every boot clean, no EXT4 errors. Slots made with orphan_file logged "orphan cleanup on readonly fs" at every mount; gone with `^orphan_file` |
| 4 | Clean shutdown | done (no change needed) | stock `Shutdown` does `killall5` then `umount -a -r`; after a normal `reboot` e2fsck reports "clean" with no journal recovery -> the data partition is remounted read-only. Not changed |
| 5 | New system accounts | done | `merge_accounts` in the first-boot step: users/groups with id < 1000 that the new image has and the machine has not (name and id free) are appended to passwd/group/shadow/gshadow (copy + rename; existing lines untouched). Test image `0.8-test3` (slot B from dev2 + group/user `gobotest` 990): after the update both appeared, `diff` of passwd = only the new line, log "accounts: adding ..." |
| 6 | grub.cfg updates | done | template `spin/ab/grub.cfg.in` (`# gobo-grub-template 1`), used by gobo-install and by gobo-update (rewrites grub.cfg when the new image's number is higher; checks; `grub.cfg.old` kept). Tested: test3 (template 2) replaced the menu; the release update replaced a dev2 menu (0 -> 1) and booted both slots incl. automatic rollback. GRUB binary never updated (documented) |
| 7 | Post-dev2 repo changes in the ISO | done | in the 0.8 image: `-O ^orphan_file` in gobo-update and gobo-install, e2fsck kernel-log lines in goboab-root, `tr -d '\000'` on the trailer line |

**Incident (fixed before the build):** the first template was cut out of the installer's here-document with its
`\$` escapes left in. gobo-update installed it on the test machine; GRUB showed entries named `$ver_a` and started
nothing. Recovered at the GRUB prompt with `configfile $prefix/grub.cfg.old`. Fixes: template cleaned;
gobo-update now refuses a rendered menu containing `\$` or failing `grub-script-check`; build-iso checks the
template. Lesson: the Bash tool of this host mangles `\$` in command strings: edit such files with the Edit tool.

### Installer menus (B)

`gobo-install` on a terminal without `--answers`/`--yes`/`--plain` uses `dialog`: welcome -> disk list (model,
size; under 32 GB "too small"; the disk holding the live medium "you started from it, cannot be used"; sr0 never
listed) -> red erase warning naming disk, model and size (default "Back") -> full name -> login (suggested from the
name; syntax, `root` and names already used by the system refused) -> password twice (stars) -> checkbox "same
password for root" (else root twice) -> computer name -> time zone region -> city -> keyboard (27 common, then all
of xkb's base.lst) -> options (autologin, text login) -> swap MB -> summary (Install/Cancel) -> gauge (copy
progress from gobo-make-system) -> "Restart now / Later". Cancel/Esc anywhere: "Quit?" (nothing changed).
`--plain` = old prompts; `--answers`/flags unchanged; the same checks run for every way of answering.
Passwords: shell variables only; hashed via `openssl passwd -6 -stdin`; hash written into shadow by awk from its
environment (no `usermod -p`, nothing on a command line); log moved to `/Data/Variable/log/gobo-install.log`
(mode 600; was `/tmp/gobo-install.log`). Checked: no password and no `$6$` hash in the log; `ps` during a password
box shows only the prompt. Screenshots `docs/screenshots/0.8-installer-*.png`.

### Tests of the final ISO (VM)

| Test | Result | Evidence |
|---|---|---|
| UEFI install through the menus, new 64 GiB disk (`vm/GoboLinux-017.01/test64.vdi`) | pass | 86 s; 16 GiB slots; "Restart now" booted the disk; LXDM login as lab; Europe/Warsaw; pl |
| BIOS install `--answers --autologin --swap 1024` on the 40 GiB disk | pass | 12 GiB slots; autologin desktop; 1 GiB swap file active; grub.cfg template 1 |
| `--plain` | pass (first prompt only) | old disk list + "(/dev/sr0 holds the installation medium ...)" |
| dev2 -> 0.8 with `GoboRefined-0.8.update` (snapshot `iso-0.8-dev-installed-efi`, dev2's own gobo-update) | pass | 48 s; boots 0.8 in slot A; look re-applied; "slot a (0.8) started fine" |
| `--rollback` and back | pass | B (0.8-dev2) then A (0.8) |
| automatic rollback | pass | 0.8 re-applied to B with 0.8's gobo-update (menu 0 -> 1), B's init broken -> two failed tries -> A, notice "rolled-back", `--status` "last rollback" |
| `vm/input-test.sh` on the UEFI menu install | pass 32/32 | |
| 0.6 spot checks (UEFI menu install) | pass | desktop Trash icon; `gio trash` -> Trash/files; Print -> `~/Pictures/Screenshots/...png`; CopyQ running, clipboard text read back by `copyq read 0`; USB stick notification at login; light mode and back (`power.toggle_mode`, screenshot); log out -> greeter -> log in; search covered by input-test scenarios |
| update cycle on the UEFI menu install | pass | `GoboRefined-0.8.update` into slot B (6.8 GB free in a 16 GiB slot), restart -> slot B running, data partition clean |

Also on the hardening machine (not the final ISO): installer pre-test with the dev2 live ISO + the new installer,
BIOS, 64 GiB disk: whole menu flow incl. "too small" disk, invalid login, system name `man`, mismatched
passwords; booted, LXDM login with the menu-set password.

### Fragile / not tested on real hardware

- Real UEFI firmware and its boot list (efibootmgr entry "GoboLinux" + removable path); NVMe names
  (`part_dev` adds `p`; never run on NVMe); the live medium being a USB stick (detection tested only with the
  virtual DVD `sr0`; for a stick it uses the parent disk of the medium's partition).
- A grub.cfg template change is shared by both slots: a broken one stops both (recovery: `configfile
  $prefix/grub.cfg.old` at the GRUB prompt). Checks catch the mistake seen in the lab, not every possible one.
- Account merge only for ids < 1000 and free names/ids; a clash is logged and skipped.
- `/System/Settings/shadow` (and gshadow) are mode 644 in stock 017.01, so password hashes are readable by every
  user. Found, NOT changed (the lock screen's PAM path may rely on it); worth an upstream report and a careful fix.
- Data partition on a 48 GB disk is smaller (12 GiB) than on a 47.9 GB one (20 GiB) because of the slot rule.
- The 0.6.2 list (`docs/roadmap.md`) is not fixed.

### VM and disks

- New disk `vm/GoboLinux-017.01/test64.vdi` (64 GiB dynamic, 22 GB on the host): SATA port 0 in the final state.
- Snapshot **`iso-0.8-installed-efi`** (taken powered off): UEFI menu install of the final ISO on test64, user lab,
  LXDM, pl, Europe/Warsaw, after one update cycle (slot B running). VM powered off, firmware EFI, DVD empty.
- Two orphaned differencing images from this session (not attached to anything, not deleted per the rules):
  `Snapshots/{76237ade-...}.vdi` (12 GB, the hardening test state) and `Snapshots/{979f1982-...}.vdi` (20 GB, the
  BIOS answers-file install). They can be removed with `VBoxManage closemedium disk <uuid> --delete` if the owner agrees.
- Rebuild: snapshot `iso-build-env-8a` as before; `vm/serve/ab.tgz`, `build-iso.sh`, `grub.cfg.in` refreshed and
  identical to `spin/`. The build VM's leftover `/Data/Build/GoboLinux-017.01-spin.iso` must be deleted before a build
  (space; it is in the snapshot).

### Lab lessons (0.8 release)

- zsh on the guest: an unmatched glob aborts the whole command line (`rm -f a *.update` deleted nothing).
- Do not force-eject the live DVD before rebooting the live session: its shutdown then hangs ("no more processes").
- `vm/ssh.sh 'cat > FILE' < local` copies a 2.7 GB update into a VM in under a minute.
- Background loops in the Bash tool are moved to the background after 3 minutes; use Monitor for long waits.

Downloads: none.

## Clean-up 2026-11-15 (owner approved)

Deleted to free disk space (107 GB → 240 GB free on C:): `dist/GoboRefined-0.5.iso`, the `0.8-dev1` and
`0.8-dev2` ISO and update files, two unreferenced VM disk images, and the snapshots `iso-0.4-installed-efi`,
`iso-0.5-installed-efi`, `iso-0.6-installed-efi`, `iso-0.8-dev-installed-efi`. Mentions of these further up
are history. Remaining snapshots: `not even installed`, `iso-build-env-2` … `-6b`, `iso-build-env-8a`,
`iso-0.8-installed-efi` (current).

## 0.8.1: first real update (bug fixes from the real-PC test) — built and update-tested (2026-11-15)

Work notes, item by item (numbers = the task list; roadmap numbers in brackets).

- **1 Wi-Fi menu [1] — done (desktop side), real PC to confirm.** The look now carries a patched copy of GoboNet's
  menu widget, `look/gobo11/awesome/spin/gobonet_menu.lua` (rc.lua requires it instead of `gobo.awesome.gobonet`).
  Interfaces are read from sysfs whenever needed instead of once at desktop start; `hotplug_check()` (called by
  `spin/network.lua` every 4 s) notices a Wi-Fi interface appearing/disappearing, brings it up
  (`gobonet_backend interface-up`, setuid) and starts a background full scan; an open menu closes on a change; Rescan
  uses the current interface. With no adapter the menu says "No Wi-Fi adapter found". Test: `vm/net-test.sh`
  (fake sysfs tree + stub backend; plug in wlan0, unplug, plug in as wlan1, Rescan, cable in/out): 18/18.
- **2 Wired entry without a cable [7] — done.** `carrier` = 0 -> "Wired network (eth0): no cable", not clickable
  (unknown carrier, i.e. interface down -> entry as before). Checked: VirtualBox `setlinkstate1 off` -> carrier 0.
- **3 Screenshot while a menu is open [8] — done.** `popups.pass(mods, key, action)` in `spin/popups.lua`: registered
  keys get through every keyboard grab; the filter closes all popups, releases the grabs, then runs the action. rc.lua
  registers Print and Win+Shift+S. New input-test scenarios `shot-print-in-menu`, `shot-card-in-menu` (screenshot
  file counted).
- **4 Win tap opens the dots menu [6] — done.** rc.lua binds Super_L: press, then release under 0.6 s with no other
  binding fired and no Win+click in between -> `mymainmenu:toggle()`. Finding: with Super_L bound, X delivers every
  key to that root grab while Win is held, so the window keys with Win (Win+F, Win+arrows ...) stopped working
  (measured: Win+Up did nothing). They are now mirrored as global keys acting on the focused window. Side effect: an
  unbound Win+key combination no longer reaches the application. Scenarios `win-tap`, `win-hold` (Win+Up still
  resizes, no menu). `vm/input-test.sh`: 41/41 (32 old + 9 new checks).
- **6 Power button [5] — desktop part tested.** Stock acpid had no rule at all (`/System/Settings/acpi/events`
  empty). New `spin/ab/gobo-power-button` (GoboSpin bin) + rule `events/gobo-power-button` written by
  `gobo-make-system`. Desktop on the foreground VT -> `awesome-client` as that user opens the power menu (second
  press closes it); otherwise `shutdown -h now`. acpid reports one press twice (netlink + input layer): the script
  acts once per second (flock + time stamp in /var/run). VM: `VBoxManage controlvm ... acpipowerbutton` -> power
  menu (screenshot checked).
- **5 USB mouse dead after re-plug [4] — cause found and fixed (VM-simulated).** Xorg's udev backend never got
  hot-plug events: Eudev's libudev subscribes a "udev" monitor only if `/dev` is a devtmpfs mount, checked with
  `name_to_handle_at("/dev", flags 0)`, which does not follow GoboLinux's `/dev -> /System/Kernel/Devices` link
  (strace: the monitor socket is bound with groups=0; udevd does broadcast, a raw netlink listener on group 2 got the
  messages). Fix: `spin/ab/gobo-udev-dev.c` (preload, follows the link for exactly the path "/dev"), built by
  build-iso into GoboSpin `lib/`; `spin/ab/gobo-xorg` wrapper; gobo-make-system points `/System/Index/bin/X` at it.
  Test: a fake USB mouse made with uinput (`python3` script, created, moved, destroyed, created again): before,
  Xorg.0.log showed nothing and the pointer did not move; after, "config/udev: Adding/removing input device" for
  both plugs and the pointer moved 100 px each time. `udevadm monitor --udev` with the preload also gets events.
  Not covered: text login (`startx` as the user runs the setuid Xorg, the loader drops LD_PRELOAD).
- **9 `/System/Settings/shadow` world-readable [14] — done.** PAM checks for normal users go through
  `unix_chkpwd`, which is setuid root on 017.01; LXDM, sudo, su are root. New mode 640 root:shadow for shadow and
  gshadow: in the image (`gobo-make-system`) and on **every start** (`secure_accounts` in `gobo-update --boot-task`;
  the account files live in the overlay, so this is what fixes existing installs; idempotent, logged once).
  Tested on the 0.8 install by hand: lab cannot `cat` it; `sudo` (lab's password) ok; `su root` ok; lock screen:
  wrong password stays locked, right one unlocks. Greeter login: see the update test.
- **8 Second user gets the chosen layout [12] — done (not yet logged in as a second user).** The look's xinitrc has
  `system_layout()` (reads `XkbLayout` from `/System/Settings/X11/xorg.conf.d/00-keyboard.conf`, else us); `apply.sh
  HOME system` writes `setxkbmap ... -layout "$(system_layout)"` and keeps that form on re-runs; build-iso applies
  the skeleton with `system`. gobo-install now writes 00-keyboard.conf for text login too (was LXDM only). Checked:
  skeleton form -> `pl` on the pl install; explicit layouts unchanged. Users created on 0.8 already have
  `-layout us` written into their own .xinitrc (cannot be told apart from a chosen us): edit by hand.
- **10 Cosmetics [13] — done; [9] desktop icon redraw — not done** (inside PCManFM's desktop code; not cheap).
  "Pcmanfm" no longer listed in the desktops list (desktop window skipped); light/dark switch comes back to the
  same desktop (`~/.cache/awesome-restart-desktop`, checked: desktop 3 of 3 kept); search has a "Displays" entry
  (LXRandR) — not clicked through.
- Session lab login at the greeter after the shadow change: works. Power button on tty2 and at the greeter: clean
  shutdown in ~3 s (next boot: "GOBO_DATA: clean", log lines "no desktop on the screen (terminal 2/7)").
- **7 Plain text files [11] — done.** L3afpad 0.8.18.1.11 (GTK 3 Leafpad fork, autotools) built in the build VM
  (`/Data/Build/src81`, `./autogen.sh && ./configure --prefix=/Programs/L3afpad/0.8.18.1.11 && make && make install`,
  `SymlinkProgram L3afpad`, ~1 min, no errors) and added to `EXTRA` in build-iso. **The build VM snapshot
  `iso-build-env-8a` does not contain it** (not re-snapshotted): a later build must repeat these steps first.
  `apply.sh` adds `text/plain=l3afpad.desktop` to `~/.config/mimeapps.list` when the user has no text/plain choice
  (new and existing users; the first-boot step runs apply.sh).
- Build: VERSION=0.8.1 (spin/build-iso.sh default; vm/serve copies refreshed), one run from `iso-build-env-8a`
  with the stock ISO hot-attached after boot (with the ISO attached at power-on the EFI firmware boots the ISO).

### Result

**`dist/GoboRefined-0.8.1.update`** (2,734,350,336 bytes, sha256 `f55a83076892183ffb289105e294647e9e1b5c63c5a4f9136fce2afee9ce75f1`)
and **`dist/GoboRefined-0.8.1.iso`** (2,867,462,144 bytes, sha256 `05049abb143ee64ff3bdf7f418c4c6b3d6c5d2ba782563b199071e23f70335ea`),
`.sha256` files next to them; checksums identical in the build VM and on the host. One build. 0.6 and 0.8 files kept.

| Update test (snapshot `iso-0.8-installed-efi` -> 0.8.1) | Result |
|---|---|
| `gobo-update --yes` with the file (copied over SSH, root-owned) | pass, 51 s, into slot A (8.1 GB used, 6.8 GB free) |
| restart -> version | slot A 0.8.1 running/default, spin-version 0.8.1, "slot a (0.8.1) started fine" |
| first-boot step | shadow/gshadow -> 640 root:shadow (logged), apply.sh for lab and root, look-version 0.8.1, light mode kept (set before the update), `text/plain=l3afpad.desktop` added, "System updated" notification (`docs/screenshots/0.8.1-updated-notification.png`) |
| greeter login as lab with shadow 640 | pass |
| `vm/input-test.sh` | 41/41 |
| `vm/net-test.sh` | 18/18 |
| power button on the desktop | power menu |
| fake USB mouse (uinput) plugged twice | Xorg adds it each time, pointer moves 100 px each time; X runs with gobo-udev-dev.so |
| second user (`useradd -m`, skeleton of 0.8.1) | `.xinitrc` has `$(system_layout)`; logged in at the greeter: `setxkbmap -query` = pl |
| `--rollback` -> 0.8 -> `--rollback` -> 0.8.1 | pass (both boots checked with `--status`) |
| fresh UEFI install from the 0.8.1 ISO (`--answers --yes`, test64) | pass, greeter login as lab to the desktop |

End state: snapshot **`iso-0.8.1-updated-efi`** (taken powered off: the 0.8 install after the update, slot A 0.8.1,
slot B 0.8; test user `second` removed). The fresh install was made after that snapshot and discarded by restoring
it. VM powered off, DVD empty. Snapshot `iso-build-env-8a` unchanged (L3afpad not in it, see item 7).

Not verifiable in the VM (real PC): Wi-Fi with a real adapter (menu re-detection is proven only with a fake sysfs
tree and stub backend), a real USB mouse/keyboard re-plug, the real power button's ACPI events, Win tap on a real
keyboard. Text login (`startx`) still has no input hot-plug.

Downloads: L3afpad 0.8.18.1.11, https://github.com/stevenhoneyman/l3afpad/archive/refs/tags/v0.8.18.1.11.tar.gz
(sha256 `86f374b2f950b7c60dda50aa80a5034b8e3c80ded5cd3284c2d5921b31652793`), GPL-2.0-or-later (source headers).

## 0.8.2 part 1: desktop fixes + Settings app (2026-11-15, work notes)

Developed on the installed system (snapshot `iso-0.8.1-updated-efi`). Not built; VERSION unchanged.

- **1 Click loss — done (VM), real PC to confirm.** `spin/gobonet_menu.lua`: upstream's
  `popup_menu_when_done` is gone; a scan re-shows the menu only when the user asked for it ("Rescan" clicked:
  shown again if no other popup is open, no adapter came/went and under 30 s; "Scanning..." with the menu open:
  refreshed only while it is still open). Adapter events and background scans never open a menu.
  `spin/popups.lua`: every click sheet (backdrop) knows its popup (`is_open`); a watchdog (0.5 s, two strikes)
  hides a sheet whose popup is gone; a click on a stale sheet hides it and focuses the window under it; menu
  show/hide errors are caught (a failing `show` used to leave the sheet up); Win+Escape hides every sheet.
  Wi-Fi notifications (`wifi_switch.lua`) are plain naughty popups: no pointer or keyboard grab found.
  `vm/net-test.sh`: 32/32 (14 new checks: adapter appears -> no menu, no sheet, a click reaches a urxvt; menu
  closed during "Scanning..." stays closed; Rescan brings it back; unplug during Rescan -> no menu; watchdog;
  click through a stale sheet).
- **2 Show-desktop strip — done (VM).** rc.lua `show_desktop_strip(s)`: 6 px wide, 1 px separator at half height
  (theme text colour at 25 %), hover = theme hover colour, tooltip "Show desktop", after the clock on every
  screen. Click: minimizes the visible windows of that screen's desktop; next click restores exactly those (and
  the focus) if nothing is showing; if a window is showing again (opened/restored since), a click hides again.
  input-test scenario `show-desktop`. Screenshot `0.8.2-show-desktop-strip.png` (light; dark not looked at).
- **3 Power menu by keyboard — done (VM).** `spin/power.lua`: arrows/Tab move a highlighted selection (hover
  colour + accent border); no selection when it opens (so Enter alone does nothing — design choice), Enter/Space
  runs, Escape/q closes; hovering = selecting. A sixth entry "Settings" appears when `gobo-settings` exists.
  input-test scenarios `power-keys`, `power-enter` (End + Enter starts Settings). Screenshot
  `0.8.2-power-menu-keyboard.png`.
- Lab lesson: after the tty2 root login, switch back to tty7 (`vm/vbox-keys.sh tty 7`) before any keyboard
  test — Ctrl+Alt+Del on the text console is init's `ctrlaltdel` and reboots the VM (happened once).
- **4 System partitions hidden from the automounter — done (rule matching in the VM).** New
  `spin/ab/gobo-system-disk` (GoboSpin bin; sh; reads /proc/self/mountinfo + /sys only): exit 0 when a kernel name
  is the disk holding `/System/Data` or one of its partitions; `--devmon-args` prints `--ignore-device` options.
  `80-gobo-internal.rules`: + GPT name `BIOSBOOT`, + GPT type `21686148-6449-6e6f-744e-656564454649` (BIOS boot),
  + `PROGRAM=="gobo-system-disk %k"` for sd*/nvme*/mmcblk*/vd*/hd*. xinitrc: devmon gets the ignore options too.
  VM: `udevadm test` + trigger: sda1 (BIOSBOOT) and every sda partition `UDISKS_SYSTEM_INTERNAL=1`, `udevil info`
  "system internal: 1"; the USB stick sdb1 not marked and still automounted. The "USB drives" place lists only
  what is mounted under /Mount/Media, so nothing more was needed there. Not tested: the system disk really
  attached over USB (VirtualBox USB disk not tried; the PROGRAM path is what covers it) — real PC to confirm
  the FAT-fs message is gone.
- **5 Wi-Fi regulatory database — done (VM).** wireless-regdb 2026.09.03 (`spin/firmware/wireless-regdb/`:
  regulatory.db, .p7s, LICENSE, SOURCE with URL + sha256). build-iso installs them into GoboSpin `lib/firmware`
  (SymlinkProgram links them into `/System/Index/lib/firmware` = `/lib/firmware`; build checks the link) — they
  come with the new tarball `vm/serve/spin-extra.tgz` (`cd spin && tar czf ../vm/serve/spin-extra.tgz firmware
  settings`), fetched by build-iso. The kernel has both signing keys built in (sforshee, wens; the db is signed
  by wens). VM: before "failed to load regulatory.db"; after `rmmod/modprobe cfg80211` and after a reboot no
  error (success is silent in 6.12).
- **6 Settings app — done (core pages a-f), see below.**

### Settings app (`gobo-settings`) — design

- **Implementation: Lua + lgi + GTK 3** (Gtk-3.0 typelib and lgi are on the image: lgi lives in
  `/System/Aliens/LuaRocks`, so `main.lua` sets `package.path` itself). Nothing to compile; the build VM needs
  nothing new (`luac -p` is the syntax check in build-iso). Files: `spin/settings/` → GoboSpin `bin/gobo-settings`
  (sh launcher, `NO_AT_BRIDGE=1`), `share/gobo-settings/{main,common}.lua` + `pages/*.lua`,
  `share/applications/gobo-settings.desktop` (app search, category Settings). Also opened from the dots menu
  ("Settings", gear icon, after Terminal) and the power menu (sixth button). `gobo-settings PAGE` opens a page.
- One window: sidebar (GtkListBox) left, GtkStack right; a page is built the first time it is shown. Colours and
  font come from the GTK theme (the light/dark switch also changes the open window).
- **How to add a page:** write `pages/<id>.lua` returning `{ id, title, icon, build = function(C) return widget
  end }` and add the id to `PAGES` in `main.lua`. `C` (`common.lua`) has `page/heading/text/button/row/output_view`,
  `message/error/confirm/form/choose_file`, `run(argv, stdin, on_done, on_line)` (async, Gio.Subprocess),
  `helper({...}, stdin, on_done, on_line)`, `people()`, `is_admin()`, `addresses()`, `desktop(lua)` (awesome-client).
  Root work = a new, strictly checked sub-command of the helper. **Placeholders** for part 2:
  `pages/bluetooth.lua`, `pages/hotspot.lua` (skeletons, not in PAGES; a comment in PAGES says where they go).
- **Root helper `gobo-settings-helper`** (GoboSpin bin, bash): run only through `sudo -A` with
  `SUDO_ASKPASS=gobo-askpass` (zenity password box "Confirm with your password (login)"). Fixed sub-commands:
  own-password, set-password, add-user, remove-user, set-admin, autologin(-status), ssh(-status), boot-ssh,
  update-status, update-install, update-rollback, report. Sets its own PATH and unsets BASH_ENV etc. (the stock
  sudoers has `!env_reset`); validates logins (`^[a-z_][a-z0-9_-]{0,30}$`, uid 1000-59999 for every change, so
  root and system accounts are refused), full names (no colon, comma, equals sign, backslash; at most 64),
  passwords (1-128 characters, no control characters, **stdin only**, hashed with `openssl passwd -6 -stdin`,
  written into shadow by awk from its environment, copy + rename: the installer's way), update files (absolute,
  `.update`, regular file; gobo-update checks owner/permissions/signature). Never: remove yourself, remove or
  demote the last administrator, demote yourself, remove a logged-in user. Log
  `/Data/Variable/log/gobo-settings.log` (what and by whom; checked that no password lands there).
- **Administrators** = group `sys` (stock sudoers `%sys ALL=(ALL) ALL`; the installer puts the first user into sys
  and lpadmin). Standard = not in sys. New sudoers lines (gobo-make-system): `%users` may run exactly
  `gobo-settings-helper own-password` and `gobo-settings-helper report` **with their own password** (sudo asking
  the current password is the old-password check), and `shutdown -r now` / `shutdown -h now` without one (the
  power menu for standard users; before, only sys could restart from it).
- **Pages:** Appearance (light/dark through the power menu's switch; wallpaper = a copy at
  `~/.config/goborefined/wallpaper`, outside what apply.sh rewrites; rc.lua `set_wallpaper` scales it to cover
  the screen, `spin_reload_wallpaper()` + `desktop_icons.refresh(force)` hand it to PCManFM). Accounts (own
  password; list; add with full name/login/password/administrator; remove with or without home, the confirmation
  names the person; administrator/standard; automatic login = LXDM `autologin=`). Updates (version; "Show both
  system slots" = `gobo-update --status`; install from file with streamed output; rollback with confirmation;
  restart). Remote access (switch; flag `/Data/Variable/lib/gobo-settings/ssh-enabled` on the data partition;
  sshd started by the helper with `-o PermitRootLogin=no -o PidFile=/Data/Variable/run/gobo-sshd.pid`, host keys
  by `ssh-keygen -A`; at boot the new BootUp line `gobo-settings-helper boot-ssh`; the page shows
  `ssh login@address` per interface). Network (adapters, addresses, gateway; opens the taskbar network menu via
  `spin_open_network_menu()`). Sound (pavucontrol), Displays (lxrandr / displays.sh --auto), Trash (1/3/6 months
  via gobo-trash-purge). About (version, kernel, CPU, memory, data partition use, graphics from lspci + Xorg
  log; "Save system report").
- **`gobo-report`** (GoboSpin bin): `~/system-report-<date>.txt` (mode 600): versions, df, lsusb, lspci -k, ip
  addr/route, iwconfig, rfkill, xinput, Xorg log tail, /proc/bus/input/devices, desktop processes, and through
  the helper (`report`; askpass on the desktop, terminal prompt on a console) the last 400 kernel messages,
  `gobo-update --status` and the gobo-update / gobo-wifi-switch / gobo-settings logs. `--no-root` skips that.
- Not done (6g, skipped as allowed): keyboard layout, timezone/date, mouse speed, startup programs, default
  programs. A second start opens a second window (no single-instance check).

### Settings app — tests (VM: installed 0.8.1 + `vm/serve/settings-dev-install.sh`)

- `vm/settings-test.sh` (the helper called as lab through sudo -A with an askpass file; the lab password is
  piped into the VM, never printed): 24/24, then `vm/settings-test.sh remove`. Refusals (bad login, remove
  self/root/bin, demote self, unknown sub-command, non-.update file); add standard user `tester` (uid 1001, only
  group users + the default groups, home on the data partition with the look, keyboard line `$(system_layout)`,
  hash in shadow, password not in the log); `sudo` refused for tester; tester changes own password through the
  helper; tester may not add users; administrator yes/no; autologin tester/off; ssh-status; report;
  update-status. **Greeter login as tester**: desktop, layout pl. Removal with home: account and folder gone.
- GUI (simulated mouse): every page opens; wallpaper chosen through the file chooser → desktop and PCManFM show
  it, kept after switching to dark (Awesome restart) and after a reboot; dark mode from the page; "Show both
  system slots" → askpass → streamed output; "Save system report" → askpass → file written (the first try showed
  that lgi's `communicate_utf8_finish` returns only the out-parameters: fixed in common.lua).
- Update through the helper as lab: `update-install ~/Downloads/GoboRefined-0.8.1.update` (lab-owned, 644) →
  slot B written in 48 s, "ready in slot B".
- Remote access: `ssh on` → `on running`, root login from the host **refused**; reboot → sshd started by BootUp
  (root still refused, i.e. it persisted); `ssh off` from the root console → `off stopped`. Not tested: a
  password login as lab from another machine (no non-interactive password tool on the host; sshd's
  PasswordAuthentication is the stock default).
- Screenshots: `0.8.2-settings-appearance-light.png`, `-accounts-dark`, `-add-person-dark`, `-updates-dark`,
  `-remote-dark`, `-about-dark`.

### Findings, not fixed

- A new user's first login shows "System updated: 0.8.1 is running (was 0.8)" (the notice is per user and the
  new user has never seen it). Cosmetic; `spin/updates.lua` could skip homes created after the update.
- GTK's file chooser sidebar lists ESP, config, efivars, proc, pts, shm, sys (GTK's own mount list; older than
  this work; every GTK Open dialog shows them).
- Lab: `pkill -f PATTERN` inside `vm/ssh.sh '...'` kills its own shell (the pattern is in its command line): use
  `pkill -f "[g]obo-..."`. The lock screen (xsecurelock after 10 min) blanks screenshots: `xset s off -dpms`.
  The Bash tool fails on here-documents containing a backslash before a backtick: use the Edit tool.

### Regression tests at the end (installed 0.8.1 + this work)

- `vm/input-test.sh`: 48/49 in the full run (old 41 + `power-keys`, `show-desktop`, `power-enter`); the one
  failure, `power-enter`, was a Settings window left open by an earlier manual check (focus stayed on it);
  re-run alone after closing it: pass. `vm/net-test.sh` 32/32. `vm/settings-test.sh` 24/24 (+ removal).

### For the image build (part 2 / next builder)

- New host archive **`vm/serve/spin-extra.tgz`** (`cd spin && tar czf ../vm/serve/spin-extra.tgz firmware
  settings`), fetched by build-iso; `ab.tgz` refreshed (gobo-system-disk, rules, gobo-make-system). `vm/serve`
  copies (build-iso.sh, ab.tgz, spin-extra.tgz, gobo11.tgz) are identical to the repo now.
- Build VM: snapshot **`iso-build-env-8b`** = 8a + L3afpad 0.8.18.1.11 (built in `/Data/Build/src81`, same
  steps as 0.8.1). Its DVD drive is EMPTY so it boots from its disk; hot-attach the stock ISO after boot (8a had
  the ISO attached and booted the live ISO first). Nothing else was needed: the Settings app is Lua (luac is
  there), regulatory.db comes from the repo. `/Data/Build/GoboLinux-017.01-spin.iso` is still there (delete it
  in the VM before building, for space).
- `vm/serve/settings-dev-install.sh` installs this work into an installed system for testing (same places).
- Not built, VERSION not changed. Expect to check after the build: the dots-menu "Settings" entry and the
  power menu's sixth button (both appear only when `/System/Index/bin/gobo-settings` exists), the new BootUp
  line, the sudoers lines, `/System/Index/lib/firmware/regulatory.db`.

### Downloads (0.8.2 part 1)

- wireless-regdb 2026.09.03, https://mirrors.edge.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-2026.09.03.tar.xz
  (sha256 `b22e0901227b820cd1c280abe681a15b773a5103a5e10dc442e94ebb34cbf58d`, matches kernel.org's sha256sums.asc), ISC.
- L3afpad 0.8.18.1.11 again for the build VM (same URL and sha256 as 0.8.1), GPL-2.0-or-later.

### VM state

Snapshots added: `iso-build-env-8b` (powered off). The VM is restored to `iso-0.8.1-updated-efi` and powered
off (all dev work on the installed system was discarded; everything is in the repo). Nothing deleted.
