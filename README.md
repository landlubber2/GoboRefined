# GoboRefined — an unofficial, modernized spin of GoboLinux 017.01

Not official GoboLinux, and not made by the GoboLinux developers. GoboRefined is a personal spin that keeps
GoboLinux 017.01's filesystem idea and tools, and replaces the parts that were broken or dated: the installer
and the default desktop look, plus a few programs compiled into the image.

- `installer/gobo-install` — a small installer that replaces the stock one (BIOS and UEFI, whole disk).
- `look/gobo11/` — the desktop look (Awesome theme, taskbar, terminal, GTK settings) and `apply.sh`.
- `spin/` — what goes into the ISO (`GoboRefined-<version>.iso`): build scripts, patches, the A/B update
  system, the Settings app and other tools.
- `build/` — **build the ISO yourself** from the stock 017.01 ISO and this repository: see **`BUILDING.md`**.
- `docs/making-apps.md` — **make an app package** that Settings > Software > Apps installs; `apps/` holds examples.
- `dist/` — the built ISO (not in git) and how to try it.
- `docs/roadmap.md` — what comes next, in stages with checkpoints; `docs/third-party.md` — third-party parts
  and their licences.
- `HANDOFF.md` — detailed state, findings about 017.01, and how to drive the test VM.
- `vm/` — helpers for the VirtualBox test VM.

Internal names stay as they were (the `gobo11` look, `/Programs/GoboSpin`, the disk label `GoboLinux`).

Start with `HANDOFF.md` and `docs/roadmap.md`.

## Licence

Our own scripts, look files and tools are licensed GPL-2.0-or-later (see `LICENSE`). Third-party components
keep their own licences; they are listed in `docs/third-party.md`.
