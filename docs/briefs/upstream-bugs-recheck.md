# Brief: re-check the upstream bug report drafts — post nothing

Read `docs/briefs/COMMON.md` first and follow it. **Not a release.** The single most important rule:
**nothing is posted, commented or submitted anywhere.** You produce final texts; the owner posts them under
their own GitHub account after reading each one.

## Background

`docs/upstream-bugs/` holds four drafts written against the GoboLinux 017.01 ISO, plus later findings that
have no draft yet. A search of upstream's tracker on 2026-11-15 showed upstream was active in 2025 (for
example gobolinux/Installer issues #19, #23, #26 about GRUB on UEFI, at least one closed), so some of our
findings may already be fixed in upstream's current code even though the 017.01 ISO still has them.

Be respectful to upstream: a small volunteer project. A report is welcome when it is verified, minimal,
not a duplicate, and offers the fix if we have one.

## Items

1. **For each existing draft** (`1-chpasswd-noop`, `2-grub-install-efi`, `3-xrandr-missing`,
   `4-graphic-boot-kdm`):
   - find the right upstream repository and read its **current** code (clone into `upstream/`, which is
     gitignored; `scripts/clone-upstream.sh` exists) — is the bug still there on the default branch?
   - search the open and closed issues and pull requests of the gobolinux organisation for the same
     problem (use the public web pages read-only; no login, no posting);
   - re-run the reproduction on the stock 017.01 ISO in the VM only if the draft's steps are unclear
     (snapshot `not even installed` boots the stock ISO; restore the previous snapshot afterwards);
   - decide: **post as new** / **comment on existing issue #N** (then rewrite the text as a short comment
     that adds our evidence) / **drop** (already fixed upstream: note the commit).
2. **Write drafts for the newer findings**, same format (version, steps, result, expected, analysis, fix):
   - the GoboNet backend loses its setuid bit on the live ISO, so normal users cannot manage Wi-Fi
     (see `HANDOFF.md`, 0.5 section);
   - **libudev monitors are deaf because `/dev` is a symlink** to `/System/Kernel/Devices`: libudev checks
     `/dev` with `name_to_handle_at` without following the link, so Xorg input hot-plug, udevil/devmon and
     any other udev listener never get events (see `spin/ab/gobo-udev-dev.c` and
     `spin/patches/udevil-0.4.4-gobo-monitor.patch` for the analysis and both workarounds). This is the
     most valuable report: give the exact libudev function, a minimal C reproducer, and the possible
     upstream fixes (make `/dev` the mount point and `/System/Kernel/Devices` the link; or patch eudev);
   - `/System/Settings/shadow` is world-readable (mode 644) on 017.01;
   - the acpid package ships no rules (power button does nothing);
   - the GoboNet Awesome widget caches the wireless interface at start-up, so adapters plugged in later
     are never scanned (we carry a patched copy: `look/gobo11/awesome/spin/gobonet_menu.lua` — offer the
     relevant part as a patch);
   - anything else marked "upstream bug" in `HANDOFF.md` — grep for it.
3. **Where we have a clean fix**, prepare it as a patch file against upstream's current code in
   `docs/upstream-bugs/patches/` with a commit message in upstream's style, and mention it in the report
   text ("I can open a pull request"). Do not open one.
4. Update `docs/upstream-bugs/README.md`: one table — finding, repository, status (post new / comment on #N
   / dropped), file with the final text, whether a patch is attached, and a suggested posting order (the
   `/dev` symlink report first, small ones after; not more than two or three per day, to avoid flooding).
5. Each final text: neutral and short, written in the first person as the owner would post it, says that it
   was found while building an unofficial spin (one sentence, with no advertisement), no mention of AI
   assistance unless the owner wants it — ask through the launching session if unsure.

## Report

The table from item 4, what changed against the old drafts, anything you could not verify, and the list of
texts waiting for the yes of the owner. State of the VM if you used it.
