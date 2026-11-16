# Claude Code instructions

## Project

**GoboRefined**: an unofficial, modernized spin of GoboLinux 017.01 for the owner's daily use — desktop look,
menu installer, A/B system updates with rollback, a Settings app, and a build that works from this
repository alone. Releases are tagged `iso-<version>`.

## Read first, in this order

1. `docs/orchestrator-guide.md` — how to run the work: the routine, the hard rules, how to brief and review
   workers, how to report to the owner. **Follow it.**
2. `docs/roadmap.md` — what is decided, done and open (newest sections at the end).
3. `HANDOFF.md` — lab notes; read the newest sections before touching the VM.
4. For A/B and update work: `docs/ab-design.md`. For building: `BUILDING.md`.

## Hard rules (details in the guide)

- Nothing is pushed, published or posted anywhere without the owner's explicit yes for that specific thing.
- Never delete snapshots, ISOs, update files or disks without the owner approving the exact list.
- Never print, copy or commit the lab password, the update-signing private key or the lab SSH private key.
- Never type passwords into logins; never snapshot a running VM; one worker uses the VM at a time.
- Report honestly: "tested in the VM" is not "works on the PC"; say what was not tested.
- The owner's usage budget is small: avoid loops, build each release once.
- Be respectful to upstream GoboLinux: contributions and well-checked bug reports, posted by the owner.

## Entry points

- Upstream: https://gobolinux.org · https://github.com/gobolinux · release 017.01
- Build: `build/build.sh` (see `BUILDING.md`) · lab helpers in `vm/`
- Tests: `vm/input-test.sh`, `vm/net-test.sh`, `vm/settings-test.sh`
