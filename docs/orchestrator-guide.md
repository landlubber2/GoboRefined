# How to run this project — guide for the session that talks to the owner

Written 2026-11-16 by the model that ran the project from 0.2 to 0.8.4, for whichever model continues.
You do not need to be clever to continue well. You need to follow the routine below and not skip its checks.
Where this guide and `HANDOFF.md` disagree about lab details, `HANDOFF.md` (newest section) wins.

## 1. What this project is

**GoboRefined**: an unofficial, modernized spin of GoboLinux 017.01 for the owner's own daily use, possibly to
be published. One owner, one tester (the owner, on a desktop PC and a ThinkPad laptop). Path of least
resistance: replace a broken piece rather than debug it for hours.

What exists (all in this repository):

| Area | Where | Notes |
|---|---|---|
| Desktop look (Awesome WM) | `look/gobo11/` | applied per user by `apply.sh`; re-applied after each update |
| Installer with menus | `installer/gobo-install` | erases a whole disk; A/B layout |
| A/B updates | `spin/ab/`, `docs/ab-design.md` | two system slots, data partition, signed update files, rollback |
| Settings app | `spin/settings/` | Lua + GTK 3; one root helper behind `sudo -A` |
| File-manager tools | `spin/gobofiles/`, `spin/patches/` | trash, folder colours, LibFM/PCManFM patches |
| Build from scratch | `build/build.sh`, `BUILDING.md` | stock ISO + repo + pinned downloads → ISO and update file |
| Plans and bug lists | `docs/roadmap.md` | the single list of what is decided, done, open |
| Lab notes | `HANDOFF.md` | long; newest sections at the end; read before touching the VM |
| Releases | `dist/` (files gitignored), tags `iso-<version>` | `dist/README.md` is the text the owner reads |

## 2. The routine for every request

1. **Read the owner's message twice.** They write short, mixed English/Polish, with typos. Answer in the
   language of their last message. If a point is unclear, do the clear points and ask about the unclear one
   at the end — do not stall the whole request.
2. **Put it in `docs/roadmap.md`** (new dated section: what was asked, what you decided). Commit.
3. **If it needs the VM, compiling, or more than a few edits: give it to a worker** (section 4). Do small
   reviews, docs and decisions yourself.
4. **When the worker reports, review before believing** (section 5).
5. **Commit, tag a release if one was built, tell the owner** (section 6).

Version numbers: next bug-fix release = last number + 0.0.1. A release is always both an ISO and an
`.update` file, built once, by `build/build.sh`, signed with the project key.

## 3. Rules that must not be broken

- **Nothing leaves this PC without the owner's explicit yes for that specific thing**: no push, no publishing,
  no posting to GoboLinux's tracker, no upload. Drafts are fine.
- **Never delete** snapshots, ISOs, update files or disks unless the owner approved that exact list.
- **Never print, copy or commit secrets**: the lab password (`vm/serve/lab-answers.env`), the update-signing
  private key (`vm/keys/`), the lab SSH private key (`vm/ssh/`). All are gitignored; keep it so.
- **Never type a password into a login**, even one the owner gives you in chat. For the owner's real PC use
  the key the owner already authorised (`vm/ssh/id_ed25519`, user and address as the owner states); read
  only, nothing that needs `sudo`.
- **Never snapshot a running VM.** Power off, snapshot, start. A live snapshot once hung for hours.
- **One worker uses the VM at a time.** Tell the owner to leave the VM alone while one runs.
- **Report honestly.** "Tested in the VM" is not "works on the PC". Say what was not tested. If a test
  failed, say so with the number.
- **The owner's usage budget is small.** Workers cost the most. Do not start one for something you can do in
  five tool calls; do not let one loop (the budget rule in section 4 goes into every brief).
- Root-run scripts: strict argument checks, no predictable file names in `/tmp`, never `rm -rf` or `mkfs`
  on a path built from an unchecked variable. Read such code yourself in review.

## 4. Writing a worker brief

Workers start with no memory of this conversation. A good brief has these parts, in this order (copy the
structure of the briefs quoted in the recent `HANDOFF.md` sections):

1. Who and where: project one-liner, workspace path, which files to read first (`CLAUDE.md`, `HANDOFF.md`,
   the roadmap section, the design doc that applies).
2. **Budget rule (always include, word for word):** "3 failed attempts or ~30 minutes without progress on
   one sub-problem → stop on it, note what you tried and the exact error, move on or hand back. Develop on
   the installed system; build the image once at the end. No polling loops. Keep HANDOFF.md notes current."
3. The items, in priority order, each with: the owner's own words or the log line that shows the problem,
   what "done" looks like, how to test it in the VM, and what cannot be tested there.
4. Delivery: version number, which snapshot to start from and which to create (names), files expected in
   `dist/`, the update test (previous release → new one, rollback and forward), docs to update.
5. Lab rules (copy the block from a previous brief): passwords, key, snapshots, no commit/tag/post.
6. Report format: per item done / partly / not done, how verified, what only real hardware can confirm,
   checksums, files changed, downloads, VM state.

If a worker stops with "usage limit" or "stalled", it is not a failure of the work: send it a message
"continue from where you stopped; first check the VM state and whether your background job finished; do not
build twice". If the owner says they are shutting the PC down: tell the worker to stop, stop the build in
the guest, `sync`, power the VM off, and take a powered-off snapshot so the build disk is not lost.

## 5. Reviewing a worker's result (do not skip)

1. `git status --short` — every new file is intended; nothing under `vm/keys`, no `.env`, no `.pem` except
   the public key.
2. `bash -n` on every changed shell script.
3. `sha256sum -c` on the new files in `dist/`.
4. **Read the risky code yourself**: anything that runs as root, formats, deletes, or handles passwords
   (`spin/settings/gobo-settings-helper`, `spin/ab/gobo-update`, `installer/gobo-install`,
   `spin/gobofiles/gobo-trash-purge`). Look for: unchecked arguments, passwords on command lines or in logs,
   files in `/tmp`, formatting without checking the target.
5. Look at one or two screenshots in `docs/screenshots/` for anything visible.
6. Note every "decision the owner might want to overrule" from the report — these go into your message.
7. Commit with a message that says what changed and what is not proven; tag `iso-<version>` for a release.

## 6. Telling the owner

Lead with the state in one sentence (ready / not ready, tested where). Then: what was fixed and how it was
checked, what was not done, side effects, what to test on the real machine (numbered, short), file names and
checksums. Plain words, no jargon the owner did not use. Never claim a fix works on their hardware until
they confirm it.

When the owner reports a problem: ask for the log before guessing. `gobo-report` (terminal, Win+Enter)
writes `~/system-report-<date>.txt`; in "safe graphics" mode use
`cp /var/log/Xorg.0.log ~/xorg.txt; sudo dmesg > ~/dmesg.txt`. Most hardware problems so far were answered
by one grep of the kernel log (`firmware`, `sof`, `error`, the device name).

## 7. Things learned the hard way

- GoboLinux's `/dev` is a symlink; libudev then ignores device events. Fixed for udevil (patch) and Xorg
  (preload library). Expect the same in any new program that waits for hot-plug.
- The installer's `ProfileInstall` replaces each program's `Settings` with its defaults: system files must
  be written by `spin/ab/gobo-make-system`, not only in the live image.
- The root is an overlay; files written at runtime hide newer files from an update. Machine settings go to
  the "install" layer; generated caches are listed in `spin/ab/generated-caches`.
- No polkit, no session D-Bus, no gvfs, no udisks, meson does not work, glibc is 2.30, GTK 3 only.
- Upstream widgets cache hardware at start-up (the Wi-Fi menu did). Hardware that appears later must be
  re-detected.
- A full-screen "click catcher" behind menus once swallowed all clicks. Any new popup must register in
  `look/gobo11/awesome/spin/popups.lua`; Win+Escape must always free the keyboard and mouse.
- New laptops fail on missing general pieces (firmware, modern driver defaults), not on anything specific to
  that laptop. Fix the general piece.
- The VM has no Wi-Fi, Bluetooth, Intel sound or touchpad. Those features ship "experimental" and the owner
  is the test.
- Tests exist and must stay green: `vm/input-test.sh`, `vm/net-test.sh`, `vm/settings-test.sh`. A stray
  window left open makes the input test fail falsely — close windows between runs.

## 8. Open items when this guide was written

See `docs/roadmap.md` for the full list. In short:

- **0.8.4 in progress**: laptop sound firmware, full firmware collection, generic graphics default,
  Bluetooth pairing agent, small fixes.
- **0.8.5 idea**: "works on machines we have never seen" — safe graphics that starts a desktop, a hardware
  check page in Settings.
- **Owner's wishes not started**: Miniconda, VS Code or VSCodium (owner to choose), a paint program;
  Bluetooth audio; more Settings pages; themed boot; Wi-Fi during install; install next to another system
  (data-loss risk: needs its own careful checkpoint).
- **Publishing**: licence is GPL-2.0-or-later (decided). Not decided: whether and where to publish, where
  the 2.9 GB ISO is hosted, source-code offer for GPL binaries, ONLYOFFICE terms (`docs/third-party.md`).
- **Upstream bug reports**: drafts in `docs/upstream-bugs/`; re-check each against upstream's current code
  first; the owner must say yes to each and posts under their own account.
- **Known bugs not fixed**: freeze when the USB Wi-Fi adapter is unplugged; desktop icons not redrawn after
  moving; file-chooser side pane lists system mounts.

## Ready-made briefs

`docs/briefs/` holds complete worker tasks for the next releases (0.8.5, 0.9.1, 0.9.2, 0.9.5, publishing
preparation, upstream bug reports). Start them as `docs/briefs/README.md` says; each brief lists questions
to settle with the owner before launching.
