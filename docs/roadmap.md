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

## Stage 1 — Desktop basics from what already ships (no new software)

- Searchable app launcher: a Start-style popup with a search box, written inside the existing desktop.
- Power menu on the taskbar: lock, log out, restart, shut down.
- Lock screen: `XSecureLock` is already on the image; wire it up and style it.
- Restyle the leftover neon pieces: battery, sound and brightness icons, the Alt+Tab switcher.
- Light mode: check it, fix it, add a one-click dark/light toggle.

**Checkpoint 1 → ISO 0.2.** Risk: low. Everything is config and Lua in `look/`.

## Stage 2 — Fonts and icons (new files, nothing to compile)

- A modern UI font and a matching monospace font (open licences only).
- A fuller icon set so apps and the launcher stop falling back to a generic icon.
- Apply both to the desktop, GTK apps and the terminal.

**Checkpoint 2 → ISO 0.3.** Risk: low. Kept separate from stage 3 so a font/icon problem is easy to spot.

## Stage 3 — Missing programs (compiled into the ISO)

In this order, each one built and tried before the next:

1. File manager.
2. Sound control window.
3. Display arrangement window (on top of the `xrandr` tool added in 0.1).
4. Wi-Fi: check what the built-in GoboNet widget already covers before adding anything.
5. Graphical login screen. Fallback if it will not build cleanly: automatic login plus the lock screen.

**Checkpoint 3 → ISO 0.4.** Risk: **medium to high.** 017.01's libraries date from around 2020, so current
versions of these programs may not build and older versions may be needed. The login screen is the least
certain item on the whole roadmap. Each program that fails is dropped or swapped, not debugged for days.

## Stage 4 — Boot experience

- GRUB menu themed to match the desktop (it is a static file our installer writes, so this is contained).
- Quieter boot: a matching boot theme instead of the stock text.

**Checkpoint 4 → ISO 0.5.** Risk: medium. A bad boot theme can hide real boot errors, so the "safe graphics"
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
