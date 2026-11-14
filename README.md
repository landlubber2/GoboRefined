# GoboRefined — an unofficial, modernized spin of GoboLinux 017.01

Not official GoboLinux, and not made by the GoboLinux developers. GoboRefined is a personal spin that keeps
GoboLinux 017.01's filesystem idea and tools, and replaces the parts that were broken or dated: the installer
and the default desktop look, plus a few programs compiled into the image.

- `installer/gobo-install` — a small installer that replaces the stock one (BIOS and UEFI, whole disk).
- `look/gobo11/` — the desktop look (Awesome theme, taskbar, terminal, GTK settings) and `apply.sh`.
- `spin/` — how the ISO (`GoboRefined-<version>.iso`) is rebuilt, and extra programs added to it.
- `dist/` — the built ISO (not in git) and how to try it.
- `docs/roadmap.md` — what comes next, in stages with checkpoints.
- `HANDOFF.md` — detailed state, findings about 017.01, and how to drive the test VM.
- `vm/` — helpers for the VirtualBox test VM.

Internal names stay as they were (the `gobo11` look, `/Programs/GoboSpin`, the disk label `GoboLinux`).

Start with `HANDOFF.md` and `docs/roadmap.md`.
