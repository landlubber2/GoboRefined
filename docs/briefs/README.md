# Ready-made worker briefs

Each file here is a complete task for one worker. They were written 2026-11-16 by the model that ran the
project up to 0.8.4, so that a later (possibly less capable) session only has to start them and review the
result. `COMMON.md` holds the rules every brief shares.

## How to start one (for the owner)

Open a session in this folder and type, for example:

> Read docs/orchestrator-guide.md. Then start a worker for docs/briefs/0.9.1-accounts-security.md and review
> its result the way the guide says.

The session should then launch one background worker whose whole prompt is:

> Read `docs/briefs/COMMON.md` and `docs/briefs/<file>.md` in `<workspace path>` and carry the brief out.
> Hand back the report it asks for.

## Rules for the session that starts them

- One brief at a time: there is one lab VM. Tell the owner to leave the VM alone meanwhile.
- Check the "Before starting" list of the brief. If it holds questions for the owner that are still open,
  ask them first and write the answers into the brief (section "Answers from the owner") before launching.
- Check that the release the brief builds on exists (`git tag`, `dist/`), and fix the version number in the
  brief if releases were made in between.
- When the worker reports: review as `docs/orchestrator-guide.md` section 5 says, commit, tag
  `iso-<version>`, report to the owner as section 6 says.
- If a worker stops on a usage limit or stalls, send it "continue from where you stopped; check the VM state
  and whether your background job finished; do not build twice".

## The briefs

| File | Result | Depends on |
|---|---|---|
| `0.8.5-sound-bluetooth.md` | laptop sound profile, Bluetooth visibility, Bluetooth sound | 0.8.4 (started 2026-11-16) |
| `0.8.6-unknown-hardware.md` | safe mode that starts a desktop; hardware check in Settings | 0.8.5 |
| `0.9.1-accounts-security.md` | "Simple" accounts for a child or grandparent, security hardening, current kernel and browser | 0.8.4 (0.8.5 if done) |
| `0.9.5-apps.md` | code editor, Conda prompt, picture and video programs, small utilities | 0.9.1 |
| `0.9.8-device-manager.md` | Device Manager: devices by category, driver state, "find a driver" suggestions | 0.8.6 (hardware check) preferably |
| `publish-prep.md` | everything ready for publishing, nothing published | any release |
| `upstream-bugs-recheck.md` | bug report drafts re-checked against upstream, ready for the owner to post | none; mostly no VM |
