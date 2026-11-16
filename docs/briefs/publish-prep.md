# Brief: prepare everything for publishing — publish nothing

Read `docs/briefs/COMMON.md` first and follow it. **Not a release; no VM needed** except for fresh
screenshots. The single most important rule of this brief: **nothing is pushed, uploaded, posted or sent
anywhere.** You prepare files in the repository; the owner publishes.

## Decisions already made by the owner

- Licence of the project's own code: GPL-2.0-or-later (`LICENSE` is committed).
- Name: GoboRefined, always described as "an unofficial spin of GoboLinux 017.01".
- Plan discussed (not yet confirmed as final): source on GitHub; the ISO and update files hosted elsewhere
  because GitHub limits release files to 2 GB (SourceForge or the Internet Archive); a one-page site; first
  audience the GoboLinux community, wider announcements later.

## Before starting (the launching session asks the owner; write answers below)

1. Where will the ISO be hosted (SourceForge / Internet Archive / split into two parts on GitHub releases)?
2. The public name or handle to show as author/maintainer, and a contact method for bug reports (GitHub
   issues only is fine).
3. Is the lab folder `vm/` meant to be public as it is? (It contains helper scripts and no secrets; secrets
   are gitignored — you verify that below.)

### Answers from the owner

(none yet)

## Items

1. **Secrets and privacy audit of the whole history, not only the current tree.** Every commit:
   `git log --all -p` searched for private keys, passwords, tokens, `.env` contents, the lab password
   value (read it from `vm/serve/lab-answers.env` into a variable for the search; never print it), host
   user names and home paths, e-mail addresses other than the GitHub no-reply address, IP addresses of the
   home network of the owner, the name of the test user on the real PC, serial numbers or MAC addresses in
   pasted logs and screenshots. Look at every screenshot in `docs/screenshots/` that shows a terminal, a
   login or a network list. Report findings as a list (file, commit, what) — **do not rewrite history
   yourself**; propose the fix (remove file in a new commit / history rewrite before first publication) and
   let the owner decide.
2. **README.md for visitors**: what it is and is not (unofficial, hobby project, one maintainer, not for
   sensitive use — link `docs/security.md` if it exists), 4–6 screenshots, the feature list in plain words
   (look, installer, A/B updates with rollback, Settings, file tools), requirements (64-bit PC, 32 GB disk,
   Secure Boot off, whole disk is erased), how to download and verify, how to write to a stick, how to
   update, known problems, how to report a bug (ask for the `gobo-report` file), how to build
   (`BUILDING.md`), licence, thanks and a link to GoboLinux. Honest tone, no marketing words.
3. **Third-party obligations** — turn the open points of `docs/third-party.md` into concrete files:
   - `docs/source-offer.md`: for every GPL/LGPL/AGPL binary we add to the ISO, where its exact source is
     (pinned URL + sha256 from `build/sources.manifest`, our patches in `spin/patches/`); for the inherited
     GoboLinux 017.01 system, point to upstream's recipes and sources and state plainly that we redistribute
     their binaries unchanged. A written offer paragraph the owner can stand behind.
   - licence texts shipped inside the image under one folder (check what is there; add missing ones for
     the programs we add);
   - ONLYOFFICE: quote the relevant terms (logo retention, trademark) and list exactly what we change (the
     launcher script and menu entry); recommend keep / make it an optional download — facts for the owner,
     not legal advice;
   - the Realtek driver firmware without a stated licence: state the fact and the option to leave the
     driver out of the public ISO (the owner needs it privately);
   - Firefox branding, fonts (OFL), Papirus (GPL-3) — one line each on what the licence asks of us.
4. **Release notes** `docs/releases/<version>.md` for the current release, generated from `dist/README.md`
   and the tags: what is new, checksums, the public key for update files (`spin/ab/update-signing.pub.pem`)
   and how updates are verified.
5. **One-page site** in `site/index.html` (single static file, no external scripts or fonts, works offline,
   light and dark): name, one-sentence description, screenshots, download button placeholder
   (`DOWNLOAD_URL`), checksum, "unofficial" notice, links. Suitable for GitHub Pages. Do not enable Pages.
6. **Repository hygiene**: `.gitignore` covers build outputs; no file over 5 MB tracked (list any);
   `CONTRIBUTING.md` (how to report bugs, how to build, coding rules in three paragraphs);
   issue templates under `.github/ISSUE_TEMPLATE/` (bug report asking for version, hardware, the
   `gobo-report` file); a `SECURITY.md` saying how to report a vulnerability privately.
7. **Draft announcements** in `docs/announce/` — one for the GoboLinux community (respectful, says what we
   changed, what we would like to give back, links to the bug reports once filed), one short for Reddit
   (r/unixporn: screenshots first; r/linux: what is technically interesting — A/B updates on GoboLinux's
   file layout), one "Show HN" text. Drafts only.
8. **Checklist for the owner** `docs/publish-checklist.md`: the exact steps in order (create the GitHub
   repository, push, upload the ISO to the chosen host, paste the URL into the site and README, create the
   release with notes and checksums, enable Pages, file upstream bug reports, post to the GoboLinux
   community, wait for feedback, then wider posts), each with the command or the click path, and what to
   double-check before each irreversible step.

## Report

What is ready, what needs a decision of the owner (list each decision with the options), findings of the
audit, files created. No VM state unless you took screenshots.
