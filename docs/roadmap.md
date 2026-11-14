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

Not a bug: `sudo` asks for the user's own password, not root's. Becomes a design point when non-admin users
are added.

### 0.7 — programs the owner asked for

- Miniconda (installs into the home folder; easy).
- VS Code (official build is proprietary; VSCodium is the open build — owner to choose).
- KolourPaint (needs many KDE libraries built first; compare with a lighter paint program before committing).

### 0.8 — A/B system updates (owner's idea; design not written yet)

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
