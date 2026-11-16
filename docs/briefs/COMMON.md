# Common part of every worker brief

Every brief in this folder starts with "Read `docs/briefs/COMMON.md` first". This file is that common part.

## Where you are

**GoboRefined**, an unofficial modernized spin of GoboLinux 017.01. Workspace: the repository root on a Windows
host (Git Bash + PowerShell) with a VirtualBox lab VM `GoboLinux-017.01`. Before touching anything read:
`CLAUDE.md`, `docs/orchestrator-guide.md` (sections 3 and 7), the newest sections of `HANDOFF.md` (lab
procedures: how to reach the VM, log in, build, test, snapshot), `BUILDING.md`, and the roadmap section your
brief names. For update or installer work also `docs/ab-design.md`; for Settings work the "0.8.2" sections of
`HANDOFF.md` (design of `spin/settings/` and its root helper, how to add a page).

## Budget rule (hard)

The usage budget of the owner is small. 3 failed attempts or ~30 minutes without progress on one sub-problem
→ stop on it, write down what you tried and the exact error, move on or hand back. Develop on an installed
system (newest `iso-<version>-updated-efi` snapshot; the root is an overlay, so files can be installed by
hand; push the look with `vm/push-look.sh`). Build the image **once** at the end with `build/build.sh`
(restartable; cached sources and programs live on the build disk of the newest `repo-build-proof*`
snapshot). A second build only if the first fails a test. No polling loops; long commands in the background.
Add short notes to `HANDOFF.md` after each finished item so an interruption loses nothing.

## Lab rules (hard)

- Never snapshot a running VM (power off → snapshot → start). Never delete snapshots, disks, ISOs or update
  files. New snapshots are taken powered off and named as the brief says.
- `vm/serve/lab-answers.env` holds the lab password: never print its value; take a screenshot before typing
  logins or answers; never leave a typed password on a console screenshot; if the root console (tty2) is in
  front, keyboard tests can press Ctrl+Alt+Del there — switch back to the desktop first.
  `MSYS_NO_PATHCONV=1` for `keyboardputstring` with paths.
- The update-signing private key is in `vm/keys/` (gitignored). Releases are signed with it through the
  builder-supplied-key path described in `HANDOFF.md`/`BUILDING.md`: read into the memory of the guest only.
  Never print it, never copy it into the image or the repository.
- File server: `node vm/serve.js` on host port 8766 (start it in the background if it does not answer).
- Do not commit, tag, push, publish or post anything. Downloads of open-source or freely redistributable
  software are allowed; each goes into `build/sources.manifest` (name, version, URL, sha256, licence) and
  `docs/third-party.md`.
- Scripts that run as root: strict argument validation, passwords only on stdin, nothing predictable in
  world-writable folders, never `rm -rf`/`mkfs` on a path or device built from an unchecked variable,
  `bash -n` clean. No secrets, host user names or personal data in tracked files.
- System facts: glibc 2.30, GTK 3 only (no GTK 2), Qt 5.14, gcc 14 (old C code needs
  `-Wno-error=incompatible-pointer-types`), autotools and cmake 3.16 work, **meson/ninja do not**; no
  polkit, no session D-Bus, no gvfs, no udisks. `/dev` is a symlink (programs relying on libudev events need
  care). Slots are read-only images; machine settings go through the overlay (`docs/ab-design.md`).
- The VM has no Wi-Fi, Bluetooth, Intel sound, touchpad or webcam. Features needing them ship marked
  "experimental"; say plainly what only real hardware can confirm.

## Release delivery (when the brief says "release")

- Set `VERSION` as the brief says. Build once. Output in `dist/`: `GoboRefined-<v>.iso`,
  `GoboRefined-<v>.update`, both `.sha256` files; checksums verified in the guest and on the host. Keep the
  existing files in `dist/`.
- Update test: restore the newest `iso-<previous>-updated-efi` snapshot, apply the new update with
  `sudo gobo-update`, restart; check the version, that the look was refreshed and the light/dark and
  wallpaper choices of the user survived, that Settings opens and each page renders; run
  `vm/input-test.sh`, `vm/net-test.sh`, `vm/settings-test.sh` (close stray windows first);
  `gobo-update --rollback` and forward again. One fresh UEFI install from the ISO with a login check.
- End state: VM powered off on a new powered-off snapshot `iso-<v>-updated-efi`; a new
  `repo-build-proof-<n>` snapshot if the build environment gained cached sources.
- Docs: `dist/README.md` (new version on top: what is new, how to update, what to confirm on real
  hardware), `HANDOFF.md` (new section), `docs/roadmap.md` (mark items), screenshots
  `docs/screenshots/<v>-*.png`.

## Report (your final message)

Per item: done / partly / not done, how it was verified, what only real hardware can confirm. Decisions you
made that the owner may want to overrule. File sizes and sha256. Test table. Size added to the image and
free space left in a 16 GiB and a 12 GiB slot. Files changed. Downloads. VM and snapshot state. Plain
language, no filler. If you stop early, say exactly where things stand and what the next command would be.
