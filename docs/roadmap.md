# Roadmap — next iterations

Written 2026-11-13. Goal set by the user: **a spin for their own daily use**. Everything on the ideas list is
wanted, spread over several sessions. Extra open-source software may be downloaded and compiled freely
(list it afterwards). The first ISO (0.1) installed and ran on the user's real PC.

Each stage ends in a **checkpoint**: ISO rebuilt, installed in the VM in BIOS and UEFI mode, a VM snapshot,
a git tag, and the user tries it on the real PC before the next stage starts. A stage is not done until its
checkpoint passes.

The order puts cheap, visible, low-risk work first and anything that can lose data last.

## Stage 0 — Foundations (short)

- Put the workspace in git (ISOs, the VM folder and the stock ISO stay out of it).
- Choose a name for the spin, so it is not mistaken for official GoboLinux. Candidates: Wavelet, Tidepool,
  Gobo Aurora — or the user's own.
- Draft the four upstream bug reports as files in `docs/upstream-bugs/` (posting them comes in stage 5).

**Checkpoint 0:** first commit exists; name decided; four drafts written. No ISO.

> **Status 2026-11-14:** name decided by the user: **GoboRefined** (always shown as "an unofficial spin of
> GoboLinux 017.01"). Applied in ISO 0.5: login screen title, GRUB entries, live welcome text, installer
> messages, ISO file name `GoboRefined-<version>.iso`. Internal names (disk label `GoboLinux`, `/Programs/GoboSpin`,
> the `gobo11` look, the ISO volume label `GOBOLINUX_LIVE_INSTALLER`) are unchanged.

## Stage 1 — Desktop basics from what already ships (no new software)

- Searchable app launcher: a Start-style popup with a search box, written inside the existing desktop.
- Power menu on the taskbar: lock, log out, restart, shut down.
- Lock screen: `XSecureLock` is already on the image; wire it up and style it.
- Restyle the leftover neon pieces: battery, sound and brightness icons, the Alt+Tab switcher.
- Light mode: check it, fix it, add a one-click dark/light toggle.

**Checkpoint 1 → ISO 0.2.** Risk: low. Everything is config and Lua in `look/`.

## Stage 2 — Fonts and icons (new files, nothing to compile) — DONE, pending real-PC test

- A modern UI font and a matching monospace font (open licences only).
- A fuller icon set so apps and the launcher stop falling back to a generic icon.
- Apply both to the desktop, GTK apps and the terminal.

**Keep this stage small (user request, 2026-11-13):** one UI font, one monospace font, one icon set, applied
once. No comparing alternatives, no fine-tuning. If it is not clearly better at the first try, ship what works.

**Checkpoint 2 → ISO 0.3.** Risk: low. May be folded into the stage 3 ISO to save a build-and-test round.

> **Status 2026-11-13:** folded into ISO 0.4 (no separate 0.3). Inter 4.1, JetBrains Mono 2.304, Papirus
> 20260801 verified on VM installs of 0.4 (BIOS and UEFI). Waiting for the user's real-PC test; no git tag yet.

## Stage 3 — Missing programs (compiled into the ISO) — DONE, pending real-PC test

In this order, each one built and tried before the next:

1. File manager.
2. Sound control window.
3. Display arrangement window (on top of the `xrandr` tool added in 0.1).
4. Wi-Fi: check what the built-in GoboNet widget already covers before adding anything.
5. Graphical login screen. Fallback if it will not build cleanly: automatic login plus the lock screen.

**Checkpoint 3 → ISO 0.4.** Risk: **medium to high.** 017.01's libraries date from around 2020, so current
versions of these programs may not build and older versions may be needed. The login screen is the least
certain item on the whole roadmap. Each program that fails is dropped or swapped, not debugged for days.

> **Status 2026-11-13:** all five done in ISO 0.4 — [x] PCManFM 1.2.5, [x] PaVuControl 4.0, [x] LxRandr 0.3.1,
> [x] Wi-Fi: GoboNet widget kept, its backend made setuid again (not tried with real Wi-Fi), [x] LXDM 0.5.3 login
> screen (default; `--text-login` keeps the console login). ISO 0.4 built and installed in the VM in UEFI
> (interactive, defaults), BIOS (`--autologin --swap 1024`) and BIOS (`--text-login`); all checks passed, see
> HANDOFF. Snapshot `iso-0.4-installed-efi`. Waiting for the user's real-PC test; no git tag yet.

> **Status 2026-11-14 (0.4 feedback → ISO 0.5):** the user tested 0.4 on the real PC; the six reported problems
> were fixed (title-bar double click, terminal paste, USB automount, TP-Link Wi-Fi mode switch + driver, ONLYOFFICE,
> "command not found" hint) and the name GoboRefined applied. **`dist/GoboRefined-0.5.iso`** built and installed in
> the VM (UEFI interactive, BIOS `--autologin --swap 1024`, BIOS `--text-login`), all checks passed except the
> Firefox paste check (not tested); see HANDOFF. A search-window keyboard bug found during testing was fixed. The
> Wi-Fi adapter can only be tested on the real PC. Snapshot `iso-0.5-installed-efi`. The boot-experience stage below
> therefore becomes ISO 0.6.

> **Status 2026-11-14 (0.5 feedback → ISO 0.6):** the user's real-PC test of 0.5 asked for fixes and new
> desktop features instead of the boot-experience stage, so **ISO 0.6** carries those: keyboard no longer stuck
> after menus (Win+Escape safety net), Wi-Fi adapter auto-switch, real network icon, virtual desktops
> (Win+Shift+Tab), screenshots (Win+Shift+S), clipboard history (Win+Shift+V), default folders, file search
> (Ctrl+F), "USB drives" entry, desktop icons + Trash, folder colours. **`dist/GoboRefined-0.6.iso`** built and
> installed in the VM (UEFI typed answers, BIOS `--autologin --swap 1024`, BIOS `--text-login`); three bugs found
> in the test were fixed before the final build (sudo rule missing on installed systems, keyboard to the desktop
> window after the window menu, desktop-icon dialogs on the wrong desktop); see HANDOFF. Open: the Wi-Fi adapter
> (real PC only), second users get a US desktop keyboard layout, no default text editor. Snapshot
> `iso-0.6-installed-efi`. Stage 4 (boot experience) moves to a later ISO.

## Stage 4 — Boot experience

- GRUB menu themed to match the desktop (it is a static file our installer writes, so this is contained).
- Quieter boot: a matching boot theme instead of the stock text.

**Checkpoint 4 → ISO 0.6** (0.5 went to the fixes for the 0.4 test). Risk: medium. A bad boot theme can hide real boot errors, so the "safe graphics"
entry stays plain.

## Stage 5 — Installer

1. Menu-driven questions (disk, timezone and keyboard from lists) using the `dialog` tool already on the image.
2. Test the options that exist but were never run: automatic login, swap file.
3. Wi-Fi during install.
4. Install next to another system (choose a partition or free space instead of the whole disk).

**Checkpoint 5 → ISO 0.6**, with item 4 behind its own extra checkpoint: it is tested in the VM against a disk
that already holds another system and data, and the user tries it only on a machine with a backup.
Risk: items 1–3 low; **item 4 is the one change that can destroy someone's data if it is wrong.**

## Stage 6 — Upstream and sharing

- Post the four bug reports (needs the user's GitHub account and a yes for each).
- Offer the fixes that are clean enough as contributions.
- Decide whether to publish the spin and its ISO.
- **Rebuild from the repository alone — done (2026-11-15):** `build/build.sh` + `BUILDING.md` build the ISO
  and update file from the stock 017.01 ISO, the checkout and pinned downloads (`build/sources.manifest`);
  proven from scratch in the VM (HANDOFF, last section). Licence inventory: `docs/third-party.md`; the
  project licence is GPL-2.0-or-later.
- Before publishing (owner): how corresponding source for the redistributed binaries is provided, and the
  other points at the end of `docs/third-party.md`.

**Checkpoint 6:** reports filed; decision on publishing made.

## Still unverified from 0.1 (carry along, test when convenient)

A physical second monitor, Wi-Fi, NVMe drives, the non-English welcome texts.

## After 0.6 — from the real-PC test of 0.6 and the brainstorm of 2026-11-14

Nothing in this section is started. Version numbers are placeholders. Order proposed (not yet confirmed by the
owner): A/B design on paper → A/B prototype → the 0.6.2 fixes delivered as the first update → new programs.

### 0.6.2 — fixes (real-PC test of 0.6)

Works on the real PC: automatic Wi-Fi mode switch (4 of 4 plug-ins, `8852au` loads, `wlan0` appears), and
everything else in 0.6 not listed here.

1. Wi-Fi menu lists networks only while some network is already connected; Rescan does not help.
2. Trouble connecting to Wi-Fi after the adapter was unplugged and plugged in again.
3. PC froze when the Wi-Fi adapter was unplugged (suspect: the out-of-tree driver; not proven, not
   reproducible in the VM). If it happens again: does the Caps Lock light still toggle?
4. A USB mouse stops working after being unplugged and plugged in again, until restart (suspect: the
   desktop gets no udev events, as with USB sticks before the udevil patch).
5. Short press of the power button does nothing.
6. Tapping the Win key alone opens the dots menu (holding it for shortcuts stays).
7. "Wired network (eth0)" is listed with no cable connected.
8. Screenshots (Win+Shift+S, Print) do not work while a menu is open.
9. Desktop icons do not redraw after being moved until an empty spot is clicked.
10. Taskbar icons of minimized windows sometimes look wrong ("just 2 apps") — owner to say what exactly.
11. Plain text files have no default program.
12. A second user gets the US keyboard layout on the desktop.
13. Cosmetic: "Pcmanfm" in the desktops list; light/dark switch jumps to desktop 1; app search misses "Displays".

**Status in 0.8.1 (first update, 2026-11-15; details in HANDOFF.md "0.8.1"):** done — 1 (Wi-Fi menu re-detects
the adapter; real PC to confirm), 4 (Xorg input hot-plug fixed; simulated in the VM, real PC to confirm),
5 (power button), 6 (Win tap), 7 (wired "no cable"), 8 (screenshots in menus), 11 (L3afpad for plain text),
12 (users added later get the install-time layout), 13 (three cosmetics), 14 (shadow 640). Partly — 2 (same fix
as 1, untested without the adapter). Not done — 3 (freeze on unplugging; skipped), 9 (desktop icon redraw),
10 (unclear report; skipped).

Not a bug: `sudo` asks for the user's own password, not root's. Becomes a design point when non-admin users
are added.

### 0.7 — programs the owner asked for

- Miniconda (installs into the home folder; easy).
- VS Code (official build is proprietary; VSCodium is the open build — owner to choose).
- KolourPaint (needs many KDE libraries built first; compare with a lighter paint program before committing).

### 0.8 — A/B system updates — RELEASE CANDIDATE BUILT (2026-11-15), pending the real-PC test

Status: `dist/GoboRefined-0.8.iso` + `GoboRefined-0.8.update`, tested in the VM (HANDOFF.md, "0.8 release
candidate"). Design and what was built: `docs/ab-design.md`. Done: two system slots + data partition,
overlay root, `gobo-update` (signed update files, `--status`, `--rollback`, `--reset-system-changes`,
automatic rollback), "without my system changes" boot entries, menu-driven installer (`dialog`), 16 GiB slots
on disks of 48 GB and more, boot menu template that updates can replace, new system accounts merged on the
first start of a new version. **Reinstall needed coming from 0.6** (whole disk erased; at least 32 GB).
**The 0.6.2 list above is NOT fixed in 0.8** — it is the planned content of the first real update.
Open: real UEFI firmware and NVMe naming; GRUB itself is never updated; `/System/Settings/shadow` is
world-readable as in stock 017.01 (found during 0.8, not changed).

Original notes (before the design):

- Partitions: boot (EFI), Root A, Root B, Data. No separate recovery partition proposed: the other root slot
  and the USB stick serve as recovery.
- Root read-only, replaced whole by an update; boot falls back to the other slot if the new one fails.
- Data keeps `/Users`, settings, logs and user-added programs.
- Hard parts to design and prototype first: (a) `/System/Settings` surviving updates while picking up new
  defaults; (b) user-added programs — leaning towards an overlay so they still appear in `/Programs`.
- Includes the installer rewrite, so Stage 5 item 1 (menu-driven installer) folds into it.
- Minimum disk size to be measured (guess: about 40 GB).

### Layout decision proposed

Keep `/Programs/<Name>/<Version>` for native programs only (it is compiled into every program and assumed by
every GoboLinux tool and recipe). Other ecosystems (Android, Windows programs) would get their own home on
the Data partition, e.g. `/Data/Android`, `/Data/Windows`, not `/Programs/android`. Android apps through
Waydroid would need Wayland; the desktop is X11.

### Added to the 0.6.2 list after the 0.8 work (2026-11-15)

14. `/System/Settings/shadow` is world-readable (mode 644) in stock 017.01: every user can read the password
    hashes. Find out what depends on it (lock screen, LXDM) and tighten it. **Done in 0.8.1** (640 root:shadow;
    nothing needed the read access: PAM uses the setuid `unix_chkpwd`).

### Prep for the first update (0.8.1 = the 0.6.2 list) — diagnosis notes, 2026-11-15

Read from upstream's widget (`look/reference/gobo-widgets/gobonet.lua`; ours wraps it in `spin/network.lua`):

- **Item 1 (Wi-Fi menu empty) — likely cause.** The widget asks `gobonet interface` for the Wi-Fi interface
  **once**, when it is created at desktop start (lines 82–84, module-level variable, never re-read), and builds
  the "Rescan" command string from it at the same moment (line 179). An adapter plugged in later is never
  picked up: quick-scan and Rescan run against no interface, so the menu shows only the wired entry and
  "Rescan" — what the owner saw. Second candidate: `wlan0` is not brought up after hot-plug, so the scan
  returns nothing until something else brings interfaces up. Fix both in our wrapper: when a wireless
  interface appears or disappears (we already poll `/sys/class/net`), bring it up and recreate the hidden
  GoboNet widget with a fresh interface name (reset the module's cached names), then refresh the icon.
  Not provable in the VM (no Wi-Fi): unit-test the re-detection with a faked `gobonet interface`, and ask
  the owner to confirm on the real PC.
- **Item 7 (eth0 listed without cable).** Line 286 adds the wired entry whenever a wired interface exists;
  check `/sys/class/net/<if>/carrier` and label it "no cable" or hide it.
- **Item 8 (screenshot while a menu is open).** Menus hold the keyboard grab; route Print / Win+Shift+S
  through the grab filter in `popups.lua` the way Win+Escape already is (close the menu, then shoot).
- **Item 4 (mouse dead after re-plug).** Check first whether Xorg gets udev events at all on this system
  (`/dev` is a symlink to `/System/Kernel/Devices`; udevil needed a patch for the same reason). If not:
  an `xorg.conf.d` fallback or a small hot-plug helper; testable in the VM with a virtual USB mouse/tablet.
- **Item 3 (freeze on unplugging the adapter)** cannot be reproduced in the VM. Do not spend worker time on
  it beyond checking whether a newer driver revision mentions a disconnect fix.
- Delivery: as `GoboRefined-0.8.1.update` (and ISO), tested by updating the `iso-0.8-installed-efi` snapshot.
  Look changes reach existing users through the first-boot `apply.sh` run — verify that on the update.

### Next update (0.8.2) — from the real-PC test of 0.8.1, 2026-11-15

Confirmed on the real PC: the update 0.8 → 0.8.1 worked.

1. "Show desktop" button: a very thin strip at the right end of the taskbar (as on Windows 11); click hides
   all windows, second click brings them back.
2. Mouse clicks stopped working (pointer still moved, keyboard worked) around plugging in or unplugging the
   Wi-Fi adapter. Suspect, not proven: a stuck popup — the network menu opens by itself after the background
   scan (`popup_menu_when_done` in `gobonet_menu.lua`) and its full-screen click-catching sheet from
   `popups.lua` stays up, or the Wi-Fi notification holds a pointer grab. Owner to try Win+Escape when it
   happens. Fix regardless: no menu may open by itself on adapter events; the sheet must never outlive its
   menu (watchdog: sheet visible with no open menu → hide).
3. A way to see what is going on without the mouse: a "System report" command (USB devices, network
   interfaces, last kernel messages, Xorg input devices, our logs) written to a file in the home folder,
   reachable from the keyboard.

### 0.8.2 — decided 2026-11-15 (owner's list + findings from the real-PC report)

Real PC confirmed: update 0.8 → 0.8.1 with the file works. The report (kernel + Xorg logs) shows the mouse was
never lost by kernel or Xorg when clicks stopped: the desktop swallowed them (stuck popup sheet suspected).

Part 1 (desktop + Settings app core):
1. Thin "show desktop" strip at the right end of the taskbar. **Done (VM).**
2. Click loss: no menu opens by itself on adapter events; the click-catching sheet cannot outlive its menu. **Done (VM; real PC to confirm).**
3. Power menu: choose with arrow keys, Enter, Escape. **Done (VM).**
4. Hide the BIOS boot partition (and every partition of the disk the system runs from, also when that disk
   is attached over USB) from the automounter and the "USB drives" place. **Done (rule matching in the VM; USB-attached system disk: real PC).**
5. Wi-Fi regulatory database (`regulatory.db` missing in the kernel log). **Done (wireless-regdb 2026.09.03; VM).**
6. **Settings app** ("control panel"): one window gathering what exists (appearance light/dark, displays,
   sound, network, trash retention, updates with slot status / apply file / rollback, about + "save system
   report") plus new: accounts (password, add/remove user, administrator or standard, automatic login),
   wallpaper, remote access (SSH on/off, off by default, shows the address). Other items from the
   "Control Panel but not here" list only where quick (keyboard layout, timezone/date, mouse speed, startup
   programs, default programs). **Done: pages Appearance (incl. wallpaper), Accounts, Updates, Remote access,
   Network, Sound, Displays, Trash, About + `gobo-report`; the quick extras were skipped. Placeholders for
   Bluetooth/Hotspot (HANDOFF, 0.8.2 part 1).**

Part 2 (needs hardware the VM lacks — shipped as experimental until the owner confirms):
7. Bluetooth (on/off, pair, connect) in the Settings app. **Done as experimental page (stock BlueZ 5.54; no controller in the VM: pairing untested; no Bluetooth audio).**
8. Wi-Fi hotspot in the Settings app. **Done as experimental page (wpa_supplicant AP mode + Dnsmasq 2.91 + iptables NAT; tested with virtual radios mac80211_hwsim; real adapter untested).**

Then: build 0.8.2 (ISO + update file), update test 0.8.1 → 0.8.2 in the VM. **Done (HANDOFF, 0.8.2 part 2). Also: new users get no old update notice, power menu starts on "Lock", Settings opens only one window; GTK file-chooser side pane (proc, sys, ESP...) still not fixed.**

### 0.8.3 — hotfix (2026-11-15)

Intel laptop graphics (ThinkPad, Tiger Lake Xe): Xorg picked the old "intel" driver and showed only a strip of
the desktop; Intel graphics now use the modesetting driver (`spin/ab/20-intel-modesetting.conf`, since 0.8.4 `20-gobo-modesetting.conf`). First
release built from the repository alone (`build/build.sh`). Built, update-tested from 0.8.2 in the VM; real
Intel laptop to confirm.

### 0.8.4 — fixes from the owner's laptop test (ThinkPad, Tiger Lake, Intel AX210), 2026-11-16

1. Laptop sound: Sound Open Firmware (sof-bin 2026.09.2, IPC3 and IPC4 trees) replaces the stock SOF 1.4.2,
   which had no Tiger Lake firmware. User space unchanged: alsa-lib 1.2.2 with its matching alsa-ucm-conf
   1.2.2 (already has a `sof-hda-dsp` profile); a current alsa-ucm-conf needs a newer alsa-lib (see below).
   Folded in (owner, 2026-11-16): **firmware collection** linux-firmware 20261019 (zstd) replaces 20250309;
   **graphics default** modesetting for i915, xe, amdgpu, radeon (`spin/ab/20-gobo-modesetting.conf`; nouveau
   untouched); **touchpads** tap to click on the synaptics driver (`spin/ab/30-gobo-touchpad.conf`).
2. Bluetooth: a pairing agent in every desktop session (`gobo-bt-agent`), the taskbar menu replaced by ours
   (on/off, paired devices, "Bluetooth settings..."), the computer's Bluetooth name = its host name, nameless
   devices under "Other devices" in Settings.
3. Accounts: removing a user also removes the user's own group.
4. Lab: `vm/input-test.sh menu-click-gtk` clicks where the menu does not cover the window; stray windows
   are closed between scenarios.
5. USB sticks: Ventoy's VTOYEFI and EFI system partitions are not automounted.
6. Keyboard layout and time zone pages: skipped (budget).

#### Bluetooth audio — what it would take (not started)

PulseAudio 13 on the image is built without its Bluetooth modules, so speakers and headphones pair but
play nothing. Needed: the SBC codec library (libsbc, ~1.4/2.0, LGPL) built first, then PulseAudio 13.0
rebuilt with `--enable-bluez5` (needs BlueZ 5 headers + D-Bus, both on the image) so that
`module-bluez5-discover`/`module-bluez5-device` and `module-bluetooth-policy` exist, plus a line in
`default.pa` (`load-module module-bluetooth-discover`, normally there behind `.ifexists`). Replacing the
stock PulseAudio program means retesting all sound. Alternative: a current PipeWire with its PulseAudio
replacement — larger change (needs newer meson/glib), not for this base.

#### Sound configuration data (ALSA UCM)

alsa-lib on the image is 1.2.2 (2020) with alsa-ucm-conf 1.2.2. Current alsa-ucm-conf files declare newer "Syntax"
versions and use features that alsa-lib 1.2.2 refuses (its message: "Incompatible syntax"), and each
alsa-ucm-conf release states the alsa-lib version it needs, so a newer alsa-ucm-conf cannot simply be
dropped in; it needs alsa-lib (and alsa-utils) updated together, which touches every program that plays
sound. The stock 1.2.2 set already has `sof-hda-dsp` (speaker, headphones with jack detection, internal and
headset microphone, HDMI), matching the card name the 6.12 SOF driver uses on HDA laptops. If it does not
apply, PulseAudio falls back to its own profile probing (output works; speaker/headphone switching and the
digital microphones may not). Laptop to confirm.

## 0.8.5 — works on machines we have never seen (proposed, not started)

- **Safe graphics that starts a desktop**: a boot menu entry / automatic fallback when X fails (e.g.
  `nomodeset` + the fbdev/vesa driver, or modesetting without glamor), so an unknown GPU still gets a desktop
  and a way to report it.
- **Hardware check page** in Settings: what the system found (graphics driver in use, Wi-Fi/Bluetooth
  adapter and whether its firmware loaded, sound card and profile, touchpad driver, missing firmware lines
  from the kernel log) with a "save report" button.

What 0.8.4 found missing on the image (not fixed there):
- no `xf86-input-libinput` (touchpads use synaptics 1.9.1; no libinput library either) — modern distributions
  use libinput for touchpads, tablets and touchscreens;
- PulseAudio 13 without Bluetooth modules (no Bluetooth audio), alsa-lib/alsa-ucm-conf 1.2.2 (2020);
- BlueZ 5.54 (2020): its host-name plugin needs systemd-hostnamed (absent), so the name is written into
  main.conf at every start; works for pairing with the new agent;
- Xorg DDX drivers from 2019 (intel 2.99.917, amdgpu/ati 19.1.0) — now bypassed with modesetting for Intel/AMD;
