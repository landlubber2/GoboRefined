# Goals

## Stated intent

- Modernize **look** (still open)
- Make the system more **functional** — **install / first boot proven painful**

## Direction update (2026-11-12, later the same day) — supersedes the decision below

**Goal:** a **modernized spin** of GoboLinux 017.01, by the path of least resistance.
Keep what works; replace what is broken or hard to modernize instead of debugging it.

1. Thin installer of our own (`installer/`), reusing upstream `ProfileInstall` for the copy and writing a static `grub.cfg` (no `grub-mkconfig`).
2. Boot to desktop by default.
3. Look: restyle what ships (desktop, GRUB, boot theme, wallpaper). Desktop choice still open.
4. Remaster the stock ISO with the above — last, once 1–3 work in the VM.

## Earlier decision (2026-11-12)

**v1 focus:** install & boot reliability.  
**Approach:** patch existing Installer/`GenGrubConf` **or** thin lab installer (disk copy + minimal `grub.cfg`).  
**Out of scope for v1:** full new ISO pipeline, unrelated desktop/site redesign, “replace GRUB with something else” as a casual swap.

See `docs/installation-bug-report.md`.

## Look — TBD (later)

- [ ] Website (gobolinux.org)
- [ ] Documentation / wiki presentation
- [x] Installer / LiveCD UX — *pain confirmed; fix path chosen above*
- [ ] Desktop / default session look (installed boot was Console/TTY; LiveCD has Awesome)
- [ ] Something else: _______________

## Functionality

- [x] Install / first boot — *blocked on GRUB config generation; manual recovery works*
- [ ] Package build / Compile / Recipes
- [ ] Updates / Freshen
- [ ] Networking / GoboNet
- [ ] Docs discoverability
- [ ] Default Graphic boot / `startx` after install

## Notes

- VirtualBox + Gobo: no working shared clipboard; use `vm/clipboard-bridge/`.
- VM install: BIOS + **msdos**; detach ISO before reboot from disk.
