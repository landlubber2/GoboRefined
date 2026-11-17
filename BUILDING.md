# Building GoboRefined

This builds the GoboRefined ISO and its update file from this repository, starting from the stock
GoboLinux 017.01 ISO. Everything else is downloaded from its upstream site at a pinned version and
checked against a pinned sha256 (`build/sources.manifest`). One script does the work:
`build/build.sh`.

## What you need

- A virtual machine (VirtualBox, QEMU/KVM, ...) or a spare PC, x86_64.
- **RAM:** 4 GB (2 GB is the minimum the script accepts).
- **Disk:** an empty disk of **40 GB** for the build (it needs 30 GB free at the first run).
  The from-scratch build of 2026-11-15 ended with 7.1 GB used (sources 0.4 GB, build root 1.5 GB,
  output 5.3 GB); while the image is made, the unpacked system tree (8.1 GB) and the packed images exist
  at the same time, so expect a peak of roughly 20 GB (estimated from those sizes, not measured).
- **Internet access** for the downloads (about 3.5 GB including the stock ISO, 1.1 GB without it; 0.8.4 added
  linux-firmware, 0.67 GB, and sof-bin, 17 MB).
- **Time:** about 80 minutes on 2 virtual CPUs and 4 GB RAM in VirtualBox (2026-11-15): downloads a few
  minutes, compiling the programs about 20 minutes (CopyQ 8 min, the Wi-Fi driver 6 min), making the image
  about 55 minutes (packing the live image and the update file, reading the stock image from the DVD).
- The stock ISO **GoboLinux-017.01-x86_64.iso** (2.4 GB). If you do not have it, the script
  downloads it from the official mirror and checks it.

## Steps

1. **Create the VM**: 4 GB RAM, 2 CPUs, NAT network, an empty 40 GB disk, the stock
   `GoboLinux-017.01-x86_64.iso` in the DVD drive (the tested build ran in BIOS mode). Download the ISO from
   https://gobolinux.org/downloads.html; its sha256 must be
   `8cd66e3e06c865c375134d099b8b483776ef16edc6d3cd617740c36f6ba53bd3`.

2. **Boot the stock live session.** The build runs in it; nothing needs to be installed. (A system
   installed from the stock ISO works the same way: skip step 3 and point `WORK` at a folder with
   enough space.) Open a terminal (Win+Enter); you are root.

3. **Network, clock and the build disk** (the live session does not start the network by itself;
   the disk name is `sda` in a VM with one disk — check with `lsblk`, everything on it is erased):

   ```sh
   dhcpcd -b enp0s3            # your interface: ip link
   date                        # must be right; if not: date -u -s 'YYYY-MM-DD HH:MM:SS'
   mkfs.ext4 -L BUILD /dev/sda
   mkdir -p /Mount/Build && mount /dev/sda /Mount/Build
   ```

4. **Get the repository** onto the build disk, e.g.:

   ```sh
   cd /Mount/Build
   git clone https://github.com/<owner>/<repository>.git goborefined
   ```

   (or copy a source tarball there and unpack it).

5. **Build:**

   ```sh
   WORK=/Mount/Build/work bash goborefined/build/build.sh
   ```

   It checks the prerequisites and says what is missing, takes the stock ISO from the DVD drive (or
   `ISO=/path/to/GoboLinux-017.01-x86_64.iso`, or downloads it), downloads and checks the sources,
   builds the programs, then the image. Output in `/Mount/Build/work/output/`:

   - `GoboRefined-<version>.iso` and `.iso.sha256` — the installable live ISO
   - `GoboRefined-<version>.update` and `.update.sha256` — the signed system update (`gobo-update`)
   - `GoboRefined-<version>.update-signing.pub.pem` — the public key built into the image
   - `GoboRefined-<version>.build.log` — the log of the run (step logs: `work/logs/`)

6. **Copy the output off the VM** before you shut it down (the live session forgets everything that
   is not on the build disk), e.g. with `scp` from the build disk, or attach the build disk to
   another machine.

If the build stops, fix the cause and run the same command again: finished downloads and program
steps are kept and skipped. `build.sh check`, `fetch`, `programs` and `image` run single parts;
`build.sh unmount` cleans up mounts left by a run that was killed. `REBUILD="libfm pcmanfm"` builds
named program steps again.

## Signing key

Update files are signed; an installed system accepts only update files signed with the key whose
public half is in its image.

- **Default:** the first build generates an RSA-3072 key pair in `WORK/keys/` (private key
  `update-signing.pem`, mode 600) and reuses it for later builds in the same work folder. The script
  prints a note: updates signed with this key apply only to systems installed from your builds, and
  official GoboRefined update files will not apply to them. Keep that file if you want to make
  updates for those systems later; it is never put into the image.
- **Your own key:** `GOBO_SIGNING_KEY=/path/to/private.pem WORK=... bash build/build.sh`. The key is
  read into memory (a copy in `/dev/shm` that is deleted afterwards); its public half goes into the
  image. Make one with `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out key.pem`.
- The project's own key is not in the repository; only the project's releases are signed with it.

## What is downloaded

Every file is listed in **`build/sources.manifest`** with version, URL, sha256 and licence: the
stock ISO, GNU xorriso (only to write the ISO; not in the image), xrandr, Inter, JetBrains Mono,
Papirus icons, Menu-Cache, LibFM, PCManFM, PaVuControl, LxRandr, LXDM, Udevil, USB-ModeSwitch, the
RTL8852AU Wi-Fi driver, ONLYOFFICE Desktop Editors (official binary), CopyQ, L3afpad, dnsmasq, the
linux-firmware collection (kernel.org), Sound Open Firmware (sof-bin), the SBC codec library and the
PulseAudio 13.0 source (only its Bluetooth modules are built and added to the stock PulseAudio).
A file whose sha256 differs is refused. Patches we apply are in `spin/patches/`; licences and
redistribution notes are in `docs/third-party.md`.

## How it works (short)

- The stock image (`gobolinux-live.squashfs` on the stock ISO) is mounted read-only. The programs
  are compiled inside a **build root**: an overlay over the stock image, used with `chroot`, so the
  machine the build runs on is not changed. Each step of `spin/build-programs.sh` installs into
  `/Programs/<Name>/<Version>` in the build root.
- `spin/build-iso.sh` then takes a fresh overlay over the stock image, copies the built programs and
  the project files from the checkout into it (installer, look, A/B system, Settings app...), builds
  the initramfs, packs the live image, makes the update file with `gobo-make-system`, signs it, and
  writes the ISO with xorriso, replaying the stock ISO's boot records.

### In the project's lab VM (for whoever builds the releases)

- Since 0.9.1 the build lives on the second disk, label **`SCRATCH091`** (60 GB), not on the old 40 GB
  disk `BUILD`: `mount LABEL=SCRATCH091 /Mount/Scratch`, then `WORK=/Mount/Scratch/work`. Check with
  `lsblk -o NAME,SIZE,LABEL` before building. The old disk has no 6.12.117 kernel and little free space:
  building there recompiles the kernel for hours. If space runs out, stop and ask; never delete old
  outputs to make room.
- Copy the checkout in fresh every time (`vm/push-repo.sh --tarball`, then `wget` it in the guest and
  unpack it); an archive already on the disk is an old one.
- Before a build, look at what is already done: `ls $WORK/state` and `/Programs/Linux` in the build
  root. A step is redone only when its inputs changed (`step_inputs` in `build/build.sh`); do not use
  `REBUILD=linux` unless the kernel itself must change.

## Known limits

- Only GoboLinux 017.01 (x86_64) is supported as the build system; the build compiles against the
  libraries of the stock image, the kernel driver against the kernel the build compiles itself (0.9.1: the newest 6.12.y, version in
  `spin/kernel-version` and `build/sources.manifest`; the compile adds 1-2 hours to the first run and about
  6 GB to the peak disk use; the image's default linker is gold, so the step passes `LD=ld.bfd`).
- The output is functionally the same as the project's releases, not bit-identical (time stamps,
  generated keys, file order).
- GitHub's source archives (`/archive/...tar.gz`) are generated on request. If GitHub ever changes
  how it compresses them, their sha256 changes and the build refuses them: compare the contents and
  update the pin in `build/sources.manifest`.
- An upstream site that moves or deletes a file stops the build at that download; put a copy with
  the same name in `WORK/sources/` and the script uses it if the sha256 matches.
- The build needs root and uses loop, squashfs and overlay mounts; it was tested in a VirtualBox VM
  in the stock live session.

## Licence

Our own scripts, look files and tools are licensed GPL-2.0-or-later (see `LICENSE`). Third-party
components keep their own licences; they are listed in `docs/third-party.md`.
