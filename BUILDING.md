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
  **Since the stage-2 build root (2026-11-20) add 15 GB** (it holds LLVM, 12 GB unpacked): a 60 GB disk, or a
  second disk for `STAGE2` (see "Stage 2" below). Later runs check 20 GB free in `WORK` for `image`/`all` and
  10 GB for `programs`.
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
  image. A key file you put into `/dev/shm` yourself (`GOBO_SIGNING_KEY=/dev/shm/name.pem`, the way to
  hand a key over without writing it to a disk) is deleted when the build ends, also after an error,
  Ctrl+C or `kill`; put it there again for the next run. Make one with `openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out key.pem`.
- The project's own key is not in the repository; only the project's releases are signed with it.

## What is downloaded

Every file is listed in **`build/sources.manifest`** with version, URL, sha256 and licence: the
stock ISO, GNU xorriso (only to write the ISO; not in the image), xrandr, Inter, JetBrains Mono,
Papirus icons, Menu-Cache, LibFM, PCManFM, PaVuControl, LxRandr, LXDM, Udevil, USB-ModeSwitch, the
RTL8852AU Wi-Fi driver, ONLYOFFICE Desktop Editors (official binary), CopyQ, L3afpad, dnsmasq, the
linux-firmware collection (kernel.org), Sound Open Firmware (sof-bin), the SBC codec library and the
PulseAudio 13.0 source (only its Bluetooth modules are built and added to the stock PulseAudio),
and (0.9.7) the GNU C library 2.38 (`glibc-2.38.tar.xz`, with the fixes of its stable branch from
`spin/patches/glibc-2.38-branch-*.patch`; step `glibc`, about 10 minutes on 6 CPUs, installed next to the build
root's own 2.30, which the build keeps using; the image step makes 2.38 the system's C library), and (0.10)
btrfs-progs 7.3 and rsync 3.5.2 (steps `btrfs-progs`, `rsync`; the installer makes the btrfs pool, `gobo-update` snapshots
and copies with rsync), and (0.10.3) libva 2.24.1 and libva-utils 2.24.0 (steps `libva`, `libva-utils`: VA-API 1.24
instead of 017.01's libva 2.7.0, which Chromium/Electron refuse as too old; `vainfo`; a few seconds each).
A file whose sha256 differs is refused. Patches we apply are in `spin/patches/`; licences and
redistribution notes are in `docs/third-party.md`.

## How it works (short)

- The stock image (`gobolinux-live.squashfs` on the stock ISO) is mounted read-only. The programs
  are compiled inside a **build root**: an overlay over the stock image, used with `chroot`, so the
  machine the build runs on is not changed. Each step of `spin/build-programs.sh` installs into
  `/Programs/<Name>/<Version>` in the build root.
- **Stage 2 (since 2026-11-20):** the stage-1 build root runs the stock glibc 2.30, on which current
  ready-made tools (llvm.org's LLVM/clang, ...) refuse to run. After the stage-1 steps (`STEPS` in
  `build/build.sh`), the stage-2 steps (`STEPS2`) run in a **second build root on glibc 2.38**, like the
  shipped system: an overlay whose lower layers are stage 1's upper folder and the stock image (so it
  has every stage-1 program without a copy), switched to Glibc 2.38 by `spin/glibc-switch.sh` (the same
  script the image step uses), with gcc's `include-fixed` headers made again for the 2.38 headers
  (gcc's `mkheaders`). It lives in `STAGE2` (default `WORK/stage2`; may be another disk). Stage 2
  holds build tools: LLVM/clang 23.1.6 (llvm.org's build), CMake 3.31.12 (Kitware's build), Python
  3.13.18, Ninja 1.13.2, Meson 1.12.1 and (0.10.4) mako/MarkupSafe/PyYAML/packaging, SPIRV-Headers,
  SPIRV-Tools, SPIRV-LLVM-Translator 23.1.3, glslang and Vulkan-Headers; and (0.10.4) the **graphics
  stack** that goes into the image: libdrm 2.4.134, libglvnd 1.7.0, Mesa 26.3.1 (LLVM linked in
  statically), the Vulkan loader and vulkaninfo (Vulkan SDK 1.4.363), glxinfo/eglinfo (mesa-demos 9.0.0).
  The image step copies those six programs from the stage-2 root's upper folder (`EXTRA2` in
  `spin/build-iso.sh`, the version that `Current` names there) and drops 017.01's Mesa 19.3.3, libdrm
  2.4.100, libglvnd 1.2.0 and LLVM 9.0.1.
  - A change in stage 1 (any stage-1 step redone) makes the stage-2 root again and redoes **every**
    stage-2 step; a change in one stage-2 step redoes it and the stage-2 steps after it.
  - Rebuild one stage-2 step: `REBUILD=meson build.sh programs` (stage-1 steps stay cached).
  - Start stage 2 from scratch: `build.sh unmount`, then delete the `STAGE2` folder (only stage 2
    is lost; it is made again by the next `build.sh programs`).
  - Disk and time: see "Stage 2 numbers" below.
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
- Build snapshot: **`repo-build-proof-16`** (2026-11-23). Same build environment as `-15`, with the two
  build disks copied into compact files (`vm/GoboLinux-017.01/build-scratch-2.vdi`, label `SCRATCH091`;
  `stage2-2.vdi`, label `STAGE2`); old release outputs removed from them.

### The lab on another computer (or after the drive letter changed)

The whole lab lives in this folder (since 2026-11-23 on an external SSD, `D:\dev`): the VM, its disks and
snapshots, `dist/`, and the gitignored internal notes. To use it on another Windows computer:

1. Install VirtualBox (7.2 or newer), Git for Windows (for `bash`) and Node.js (for `vm/serve.js`).
2. Plug in and unlock the drive (BitLocker password). Never unplug it while the VM runs.
3. If VirtualBox already lists `GoboLinux-017.01` from an old place: `VBoxManage unregistervm GoboLinux-017.01`
   (**never** with `--delete`).
4. `bash vm/register-vm.sh`: rewrites the disk and ISO paths in the VM's settings file to this folder and
   registers the VM. It ends with "all disks found".
5. If VirtualBox's own list (`%USERPROFILE%\.VirtualBox\VirtualBox.xml`, `<MediaRegistry>`) still holds disks
   of this VM under an old path, registering fails with `E_INVALIDARG`: the VM's settings file already lists
   every disk, so those global entries can be removed (keep a copy of the file; VirtualBox closed).
6. The R2 upload tool (rclone) and its keys, and the git login, are set up per computer; they are not here.

### Stage 2 numbers (measured 2026-11-20, VirtualBox, 6 vCPU, 8 GB RAM)

- **Downloads:** +1.3 GB (LLVM 23.1.6 `.tar.zst` 1.2 GB, CMake 55 MB, Python 23 MB, Meson 2.5 MB, Ninja 0.1 MB).
- **Disk:** the stage-2 root's upper folder is **12 GB** (LLVM unpacked 12 GB: llvm.org ships every tool and the
  static libraries; CMake 175 MB, Python 103 MB). `build.sh` asks for 15 GB free in `STAGE2` before LLVM is unpacked.
  The lab keeps `STAGE2` on its own 80 GB disk (`STAGE2=/Mount/Stage2/stage2`).
- **Time:** making the root (glibc switch, gcc `mkheaders`, a compile test) about 1 minute; `llvm` 39 s (unpacking),
  `cmake` 6 s, `python` 3 min, `ninja` and `meson` seconds; the whole `build.sh programs` with stage 1 cached and
  stage 2 from scratch 4 min 43 s; with everything cached 22 s.
- **0.10.4 graphics steps** (measured 2026-11-20/21, same VM): +125 MB downloads; spirv-tools 10 min, spirv-translator
  4 min, glslang 7 min, vulkan 1.5 min, libdrm/libglvnd/mesa-demos seconds, **mesa 31 min** (3,283 build steps, at most
  2 links at a time for memory): about 54 min in all; the stage-2 upper grows to 13 GB. The image step stays ~12 min.
- **Linker:** 017.01's default `ld` is GNU gold 2.33.1, which mislinks undefined weak hidden symbols (Mesa's Vulkan
  drivers crashed). The stage-2 steps whose programs go into the image link with `ld.bfd` (`LDFLAGS=-fuse-ld=bfd`).
- **Needs:** zstd unpacks llvm.org's archive only with `--memory=2048MB` (1 GiB window), so about 1.1 GB of RAM
  for that step.

## Known limits

- Only GoboLinux 017.01 (x86_64) is supported as the build system; the build compiles against the
  libraries of the stock image (stage 2: the same, but with the built Glibc 2.38 as the C library), the kernel driver against the kernel the build compiles itself (0.9.1: the newest 6.12.y, version in
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

## Update file format (0.10)

The update file ends with an 8 KiB signed trailer whose first line is `GOBOREFINED-UPDATE 2` (0.10, the
btrfs layout; the manifest also says `layout=btrfs`). Format 1 was 0.8-0.9.x (ext4 slots): a 0.9.x
`gobo-update` refuses format 2 files, and 0.10 refuses format 1 files, so neither layout can be given the
other's system by mistake. Installed 0.8-0.9.x systems are reinstalled for 0.10.
