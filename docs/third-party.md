# Third-party components in GoboRefined

What the GoboRefined ISO (and update file) contains besides the project's own files, with the
licence each upstream states, where it comes from, and whether we change it. Facts only, gathered
from the sources and from `HANDOFF.md`; this is not legal advice. Pins (version, URL, sha256) are
in `build/sources.manifest`.

The project's own scripts, look files and tools (`installer/`, `look/gobo11/`, `spin/ab/`,
`spin/settings/`, `spin/gobofiles/`, `spin/gobo-*`, `spin/lxdm/` files, the patches in
`spin/patches/`, `build/`) are GPL-2.0-or-later (owner's decision; `LICENSE` at the repository root).

## Added by GoboRefined (built or copied into the image)

| Component | Version | Licence (as stated upstream) | Source | Changed by us? |
|---|---|---|---|---|
| xrandr (program `XRandR-Tool`) | 1.5.2 | X.Org permissive licence (COPYING; HPND-style) | https://www.x.org/releases/individual/app/xrandr-1.5.2.tar.xz | no |
| Inter | 4.1 | SIL Open Font License 1.1 | https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip | no (10 of the static TTF files copied unchanged) |
| JetBrains Mono | 2.304 | SIL Open Font License 1.1 | https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip | no (6 TTF files copied unchanged) |
| Papirus icon theme (Papirus, -Dark, -Light) | 20260801 | GPL-3.0 (LICENSE) | https://github.com/PapirusDevelopmentTeam/papirus-icon-theme | trimmed: only sizes 16–64 copied, `index.theme` lists only those folders (`spin/build-programs.sh`, step `papirus`); icon files unchanged. `gobo-folder-colour` makes recoloured copies of one folder icon at run time in the user's home |
| Menu-Cache | 1.0.2 | LGPL-2.1-or-later | https://downloads.sourceforge.net/lxde/menu-cache-1.0.2.tar.xz | no (compiler flags only) |
| LibFM | 1.2.5 | GPL-2.0 (COPYING); most library sources carry LGPL-2.1-or-later headers | https://downloads.sourceforge.net/pcmanfm/libfm-1.2.5.tar.xz | **yes**: `spin/patches/libfm-1.2.5-gobo.patch`; shortcut-editor menu entry hidden |
| PCManFM | 1.2.5 | GPL-2.0-or-later | https://downloads.sourceforge.net/pcmanfm/pcmanfm-1.2.5.tar.xz | **yes**: `spin/patches/pcmanfm-1.2.5-gobo.patch`; "Desktop Preferences" entry hidden |
| PaVuControl | 4.0 | GPL-2.0-or-later | https://freedesktop.org/software/pulseaudio/pavucontrol/pavucontrol-4.0.tar.xz | no |
| LxRandr | 0.3.1 | GPL-2.0-or-later | https://downloads.sourceforge.net/lxde/lxrandr-0.3.1.tar.xz | menu entry icon name changed (sed in the build step) |
| LXDM | 0.5.3 | GPL-3.0-or-later | https://downloads.sourceforge.net/lxde/lxdm-0.5.3.tar.xz | configuration and theme replaced by `spin/lxdm/` (our files; theme started as a copy of LXDM's "Industrial" theme with its files removed/replaced); program code unchanged |
| Udevil (+ devmon) | 0.4.4 | GPL-3.0-or-later | https://github.com/IgnorantGuru/udevil/archive/refs/tags/0.4.4.tar.gz | **yes**: `spin/patches/udevil-0.4.4-gobo-monitor.patch`; `udevil.conf` edited; a small `mount.ntfs` helper added |
| USB-ModeSwitch | 2.6.1 | GPL-2.0-or-later | https://www.draisberghof.de/usb_modeswitch/usb-modeswitch-2.6.1.tar.bz2 | no (only the `usb_modeswitch` binary and man page; our udev rule and `gobo-wifi-switch` added) |
| rtl8852au (Realtek RTL8852AU/RTL8832AU USB Wi-Fi driver, program `RTL8852AU`) | git 865ab0f (2024-05-06) | GPL-2.0 (driver); contains Realtek firmware as C arrays | https://github.com/lwfinger/rtl8852au | no (built out of tree for kernel 6.12.16-Gobo) |
| ONLYOFFICE Desktop Editors | 10.0.0 | AGPL-3.0 (with the additional terms in its `LICENSE`); bundles third-party libraries (Qt 5, Chromium Embedded Framework, ICU and others, listed in its `3DPARTYLICENSE`) | https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v10.0.0/onlyoffice-desktopeditors-x64.tar.xz (official binary build) | binaries unchanged; their launcher script is edited (install path, `--system-title-bar`) and their menu entry edited (path, three MIME types removed) |
| CopyQ | 6.4.0 | GPL-3.0-or-later | https://github.com/hluk/CopyQ/archive/refs/tags/v6.4.0.tar.gz | **yes**: the Wayland clipboard part removed with `sed` in the build step (`spin/build-programs.sh`, step `copyq`) |
| L3afpad | 0.8.18.1.11 | GPL-2.0-or-later (source headers) | https://github.com/stevenhoneyman/l3afpad/archive/refs/tags/v0.8.18.1.11.tar.gz | no |
| dnsmasq | 2.91 | GPL-2.0 or GPL-3.0 (COPYING, COPYING-v3) | https://thekelleys.org.uk/dnsmasq/dnsmasq-2.91.tar.xz | no |
| wireless-regdb (`regulatory.db`, `.p7s`) | 2026.09.03 | ISC | https://mirrors.edge.kernel.org/pub/software/network/wireless-regdb/ | no (files kept in `spin/firmware/wireless-regdb/`) |
| linux-firmware (program `Linux-Firmware`, replaces the stock 20250309-GIT) | 20261019 | many redistributable firmware licences, one per file group, listed in its `WHENCE` and `LICENCE.*`/`LICENSE.*` files (copied to `share/doc/linux-firmware/`) | https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/linux-firmware-20261019.tar.xz | installed by its own `copy-firmware.sh --zstd`; **left out**: `qcom`, `mellanox`, `mrvl/prestera`, `netronome`, `qed`, `liquidio`, `dpaa2` (ARM SoC, switch and server-NIC firmware, 476 MB); `intel/sof*` and `regulatory.db` removed (they come from sof-bin and wireless-regdb); 176 files of the stock 20250309 set that upstream has dropped are kept from the stock image (step `linux-firmware`) |
| Sound Open Firmware, sof-bin (program `SOF-Firmware`, replaces the stock 1.4.2) | 2026.09.2 | BSD-3-Clause with Intel's limited patent licence (`LICENCE.Intel`), BSD-3-Clause (`LICENCE.NXP`); copied to `share/doc/sof-firmware/` | https://github.com/thesofproject/sof-bin/releases/download/v2026.09.2/sof-bin-2026.09.2.tar.gz | no (all `sof*` trees copied as `install.sh` does; its debugging tools left out) |
| SBC (program `SBC`) | 2.0 | LGPL-2.1-or-later (library) | https://mirrors.edge.kernel.org/pub/linux/bluetooth/sbc-2.0.tar.xz (sha256 matches kernel.org sha256sums.asc) | no (built without the tester) |
| PulseAudio Bluetooth modules (`libbluez5-util`, `module-bluez5-*`, `module-bluetooth-*`; added to the stock PulseAudio 13.0) | 13.0 | LGPL-2.1-or-later (PulseAudio; its `LICENSE`, `LGPL` in `/Programs/PulseAudio-Bluetooth/13.0/share/doc` of the build root) | https://www.freedesktop.org/software/pulseaudio/releases/pulseaudio-13.0.tar.xz (sha256 matches the published `.sha256`) | no; built from the release tarball with BlueZ 5 enabled, only these five files kept |
| Linux kernel (program `Linux`, replaces the stock 6.12.16) | 6.12.117 | GPL-2.0-only (with the syscall note) | https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.117.tar.xz (sha256 matches kernel.org sha256sums.asc) | no source change; the stock kernel's configuration through `make olddefconfig`; the program's `build` tree holds headers and scripts only (step `linux`) |
| Intel processor microcode (program `Intel-Microcode`) | 20261110 | Intel microcode licence: redistribution in binary form allowed, no modification or reverse engineering (its `license` file, copied to `share/doc/intel-microcode/`) | https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/archive/refs/tags/microcode-20261110.tar.gz | no (the `intel-ucode` files only; dracut puts them into the early part of the initramfs) |
| Firefox ESR (program `Firefox`, replaces the stock 136.0) | 153.7.0esr | MPL-2.0; Mozilla's official binary with Mozilla's branding (see point 5 below) | https://ftp.mozilla.org/pub/firefox/releases/153.7.0esr/linux-x86_64/en-US/firefox-153.7.0esr.tar.xz (sha256 matches the release's SHA256SUMS) | binary unchanged; added `distribution/policies.json` (`DisableAppUpdate`), the stock launcher script, menu entry and icon |
| CA certificate bundle (Mozilla's list as extracted by the curl project) | 2026-11-05 | MPL-2.0 | https://curl.se/ca/cacert-2026-11-05.pem (sha256 matches the published `.sha256`) | no (copied over the image's bundle files, step `ca-bundle`) |
| GNU C library (program `Glibc` 2.38; becomes the system's C library, the stock 2.30 stays in `/Programs/Glibc/2.30`) | 2.38 + stable-branch fixes up to commit 1970e818 (2026-11-18) | LGPL-2.1-or-later (most of the library); some parts under other free licences listed in its `COPYING`, `COPYING.LIB`, `LICENSES` | https://ftp.gnu.org/gnu/glibc/glibc-2.38.tar.xz (GPG signature checked) + https://sourceware.org/git/glibc.git branch `release/2.38/master` | **yes**: `spin/patches/glibc-2.38-branch-1970e818.patch` = the upstream stable-branch fixes (security fixes such as CVE-2023-4911); GoboLinux path changes from the upstream recipe (`/var/lib/nss_db`, `/var/cache/nscd`, the include/net check off) with `sed` (step `glibc`); built with `--enable-crypt`, all locales |
| Btrfs-Progs (program `Btrfs-Progs`; 0.10 btrfs layout, prototype: not in an image yet) | 7.3 | GPL-2.0-only (libbtrfsutil LGPL-2.1-or-later) | https://mirrors.edge.kernel.org/pub/linux/kernel/people/kdave/btrfs-progs/btrfs-progs-v7.3.tar.xz (sha256 equals kdave's `sha256sums.asc`) | no (built without convert, Python, documentation, libudev) |
| rsync (program `Rsync`; 0.10 btrfs layout, prototype: not in an image yet) | 3.5.2 | GPL-3.0-or-later | https://download.samba.org/pub/rsync/src/rsync-3.5.2.tar.gz | no (built without xxhash and man pages) |
| LibVA (program `LibVA`; 0.10.3, replaces 017.01's 2.7.0) | 2.24.1 | MIT | https://github.com/intel/libva/releases/download/2.24.1/libva-2.24.1.tar.bz2 | no (built without Wayland; driver folder /usr/lib/dri as the stock build) |
| libva-utils (program `LibVA-Utils`; 0.10.3: vainfo) | 2.24.0 | MIT | https://github.com/intel/libva-utils/releases/download/2.24.0/libva-utils-2.24.0.tar.bz2 | no (built without Wayland and unit tests) |
| Mesa (program `Mesa`; 0.10.4, replaces 017.01's 19.3.3) | 26.3.1 | MIT for most of it; parts under other permissive licences (`docs/license.rst`, copied to the program's `doc/`) | https://archive.mesa3d.org/mesa-26.3.1.tar.xz | no (X11 only; Gallium nouveau, iris, crocus, radeonsi, r600, svga, zink, llvmpipe, softpipe; Vulkan intel, amd, swrast, 0.10.7: + nouveau (NVK) and the device-select layer; VA-API with Mesa's default free codecs only). **Contains LLVM 23.1.6** (Apache-2.0 WITH LLVM-exception), statically linked from llvm.org's build. 0.10.7: NVK contains Rust code compiled from Mesa's own sources plus the crates paste 1.0.14, rustc-hash 2.1.1 (MIT OR Apache-2.0 / Apache-2.0 OR MIT) and, at build time only, syn 2.0.87, proc-macro2 1.0.86, quote 1.0.35, unicode-ident 1.0.12 (MIT OR Apache-2.0; unicode-ident also Unicode-DFS-2016) |
| libdrm (program `LibDRM`; 0.10.4, replaces 2.4.100) | 2.4.134 | MIT | https://dri.freedesktop.org/libdrm/libdrm-2.4.134.tar.xz | no |
| libglvnd (program `LibGLVnd`; 0.10.4, replaces 1.2.0) | 1.7.0 | MIT-style (README.md) | https://gitlab.freedesktop.org/glvnd/libglvnd/-/archive/v1.7.0/libglvnd-v1.7.0.tar.gz | no (EGL vendor folders as 017.01's build) |
| Vulkan loader (program `Vulkan-Loader`; 0.10.4) | 1.4.363 (Vulkan SDK 1.4.363.0) | Apache-2.0 | https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz | no (X11 only) |
| vulkaninfo (program `Vulkan-Tools`; 0.10.4) | 1.4.363 | Apache-2.0 | https://github.com/KhronosGroup/Vulkan-Tools/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz | no (only vulkaninfo built) |
| glxinfo, eglinfo, glxgears (program `Mesa-Demos`; 0.10.4) | 9.0.0 | MIT | https://archive.mesa3d.org/demos/mesa-demos-9.0.0.tar.xz | no (only these three programs installed) |
| cryptsetup (program `CryptSetup`; 0.10.7, replaces 017.01's 2.3.0) | 2.8.8 | GPL-2.0-or-later (tools), LGPL-2.1-or-later (libcryptsetup) | https://cdn.kernel.org/pub/linux/utils/cryptsetup/v2.8/cryptsetup-2.8.8.tar.xz | no (OpenSSL backend, internal Argon2; no SSH or external token plugins, no OPAL). Opens BitLocker volumes with a clear key read-only |
| GoboNet menu widget (`look/gobo11/awesome/spin/gobonet_menu.lua`) | from GoboNet 0.12 | GPL-3.0 (GoboNet) | https://github.com/gobolinux/GoboNet | **yes**: a patched copy of upstream's widget lives in our look (see `HANDOFF.md`, 0.8.1) |

Used only to build, not shipped: GNU xorriso 1.5.6.pl02 (GPL-3.0-or-later), writes the ISO.

Used only to build, not shipped (stage-2 build root on glibc 2.38, build-environment jump of 2026-11-20; build
tools for the graphics stack of 0.10.4; pins in `build/sources.manifest`):

| Component | Version | Licence (as stated upstream) | Source | Changed by us? |
|---|---|---|---|---|
| LLVM + clang, llvm.org's release build (`LLVM-23.1.6-Linux-X64`) | 23.1.6 | Apache-2.0 WITH LLVM-exception (parts of the bundled runtime libraries: see the LICENSE.TXT files in the archive) | https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.6/LLVM-23.1.6-Linux-X64.tar.zst | no (unpacked as `/Programs/LLVM/23.1.6`). 0.10.4: llvm.org's build has no libLLVM.so; its static libraries are linked into Mesa, see the Mesa row above |
| CMake, Kitware's binary release | 3.31.12 | BSD-3-Clause (the binary bundles curl, OpenSSL, zlib and other libraries under their own licences: `doc/cmake-3.31/` in the archive) | https://github.com/Kitware/CMake/releases/download/v3.31.12/cmake-3.31.12-linux-x86_64.tar.gz | no |
| Python | 3.13.18 | PSF-2.0 (Python Software Foundation License Version 2) | https://www.python.org/ftp/python/3.13.18/Python-3.13.18.tar.xz | no (built without PGO, ensurepip and the test suite; installed as `python3.13` only) |
| Ninja, the release's Linux binary | 1.13.2 | Apache-2.0 | https://github.com/ninja-build/ninja/releases/download/v1.13.2/ninja-linux.zip | no |
| Meson | 1.12.1 | Apache-2.0 | https://github.com/mesonbuild/meson/releases/download/1.12.1/meson-1.12.1.tar.gz | no (run from its source tree by Python 3.13) |
| Python modules mako, MarkupSafe, PyYAML, packaging (0.10.4, into Python 3.13) | 1.4.3, 3.0.4, 6.0.3, 26.3 | MIT, BSD-3-Clause, MIT, Apache-2.0 OR BSD-2-Clause | PyPI (URLs in `build/sources.manifest`) | no |
| SPIRV-Headers (0.10.4) | commit cb42dec (after Vulkan SDK 1.4.363.0) | MIT | https://github.com/KhronosGroup/SPIRV-Headers/archive/cb42dec3830d3ac67fa449ecdc0c0f73d5e74498.tar.gz | no |
| SPIRV-Tools (0.10.4) | Vulkan SDK 1.4.363.0 | Apache-2.0 | https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz | no (static libraries; only in Mesa's build-time compiler) |
| SPIRV-LLVM-Translator (0.10.4) | 23.1.3 | Apache-2.0 WITH LLVM-exception | https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive/refs/tags/v23.1.3.tar.gz | no (static library; only in Mesa's build-time compiler `mesa_clc`) |
| glslang (0.10.4) | Vulkan SDK 1.4.363.0 | BSD-3-Clause and others (LICENSE.txt) | https://github.com/KhronosGroup/glslang/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz | no |
| Vulkan-Headers (0.10.4) | 1.4.363 | Apache-2.0 OR MIT | https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz | no |
| Rust (official standalone installer, components rustc, cargo, rust-std; 0.10.7) | 1.100.0 | MIT OR Apache-2.0 (the bundled LLVM inside rustc: Apache-2.0 WITH LLVM-exception) | https://static.rust-lang.org/dist/rust-1.100.0-x86_64-unknown-linux-gnu.tar.xz | no (unpacked as `/Programs/Rust/1.100.0`; nothing of it in the image) |
| bindgen-cli, cbindgen (0.10.7, built with that cargo) | 0.72.1, 0.29.2 | BSD-3-Clause, MPL-2.0 | https://static.crates.io/crates/bindgen-cli/0.72.1/download, https://static.crates.io/crates/cbindgen/0.29.2/download | no |
| The crates of bindgen-cli's and cbindgen's Cargo.lock (0.10.7; 123 crates, each pinned in `build/sources.manifest` with its licence as its Cargo.toml states it: mostly MIT OR Apache-2.0; also MIT, Unlicense OR MIT, ISC, BSD-3-Clause, MPL-2.0, Unicode-3.0, BSL-1.0 options) | as locked | see `build/sources.manifest` (step `rust`) | https://static.crates.io/crates/ | no (build tools only) |

## App packages (not in the image; offered on the website, installed through Settings › Apps)

Built by `apps/<name>/build.sh` from the sources below (sha256 pinned in the script); the packages are in
`dist/apps/` and on the website.

| Package | Version | Licence | Source | Changed? |
|---|---|---|---|---|
| Photos (ours, `apps/photos/`) | 1.1 | MIT | this repository | ours |
| LXTask (`LXTask--0.1.12`) | 0.1.12 | GPL-2.0-or-later | https://github.com/lxde/lxtask/archive/refs/tags/0.1.12.tar.gz | GTK 3 build; menu name "Task Manager", system icon |
| Qalculate! (`Qalculate-GTK--5.13.0`): libqalculate 5.13.2 + qalculate-gtk 5.13.0 | 5.13 | GPL-2.0-or-later | https://github.com/Qalculate/libqalculate/releases/download/v5.13.2/libqalculate-5.13.2.tar.gz, https://github.com/Qalculate/qalculate-gtk/releases/download/v5.13.0/qalculate-gtk-5.13.0.tar.gz | no source change; library inside the program folder, developer files removed |

## Inherited from the stock GoboLinux 017.01 ISO

The ISO is the stock 017.01 live ISO with a repacked live image; the stock image's ~450 programs
(kernel, GoboLinux's own tools, Xorg, GTK, Qt, Awesome, Firefox, ...) are redistributed unchanged,
each under its own licence. The boot loader files (isolinux, the UEFI `efiboot.img`) are replayed
unchanged from the stock ISO. Stock files we change in the image: the `CommandNotFound` hook and
`bashrc` lines of GoboLinux's Scripts (`sed` in `spin/build-iso.sh`), the sudoers file (added
rules), the skeleton home (our look), the live welcome text, GoboNet's backend gets back its setuid
bit, and the initramfs is rebuilt with our dracut module.

## Points that deserve the owner's attention

These are observations, not conclusions:

1. **Source for the binaries we redistribute.** The ISO contains GPL/LGPL/AGPL programs as
   binaries (our additions above and the whole stock system). Those licences attach conditions to
   distributing binaries (making the corresponding source available in one of the ways each licence
   names). Today the repository has the build scripts, patches and the URL list; the sources
   themselves are on the upstream sites. How the project will provide corresponding source alongside
   published ISOs (e.g. a source archive next to each release, mirroring `WORK/sources/`) is an open
   question. The same applies to the stock 017.01 programs inherited unchanged.
2. **ONLYOFFICE.** Redistributed as the vendor's binary build under AGPL-3.0; its `LICENSE` adds
   terms under AGPL section 7 (about the product logo and trademarks), and it bundles many
   third-party libraries with their own licences (`3DPARTYLICENSE` in the package). We edit their
   launcher script and menu entry. Worth reading those files before publishing.
3. **Realtek driver (rtl8852au).** The driver code is GPL-2.0, but it carries Realtek's Wi-Fi
   firmware as C arrays inside the source; the repository states no separate licence for that
   firmware. Out-of-tree driver from a third-party GitHub repository, not from Realtek or the kernel.
4. **Fonts (Inter, JetBrains Mono).** SIL OFL 1.1 allows bundling with software. We copy a subset of
   the files unchanged; the licence restricts the font names for modified versions (we do not
   modify them) and asks that the licence travel with the fonts (installed in each program's `doc/`).
5. **Firefox.** Up to 0.8.5 the image contained the stock Mozilla Firefox 136.0 binary; from 0.9.1 it is
   Mozilla's official Firefox ESR binary (153.7.0esr), with Mozilla's branding. Mozilla's trademark policy
   governs redistribution of the branded build: the binary is passed on unchanged; the only addition is a
   policy file that switches its self-updater off (the program folder is read-only). Whether that
   still counts as "unmodified" for the trademark policy is a point to settle before publishing.
6. **GPL-3.0 components next to GPL-2.0-or-later code.** Papirus, LXDM, Udevil, CopyQ, GoboNet's
   widget are GPL-3.0(-or-later); ONLYOFFICE is AGPL-3.0. Our code being GPL-2.0-or-later allows it
   to be combined with GPL-3.0 code (under GPL-3.0). Two places where our code and GPL-3.0 code are
   in the same work: the Udevil patch (`spin/patches/udevil-0.4.4-gobo-monitor.patch`, applied to
   GPL-3.0-or-later code) and the patched GoboNet widget in `look/gobo11/awesome/spin/`
   (GPL-3.0 upstream code inside the look). Nothing of ours is GPL-2.0-only, so no conflict is known;
   the GoboNet widget file may need GoboNet's GPL-3.0 notice rather than ours.
7. **Names and logos.** "GoboLinux" and its artwork belong to the GoboLinux project; the spin calls
   itself "an unofficial spin of GoboLinux 017.01" and keeps stock names in places (volume label,
   boot menu of the live ISO, `/Mount/GoboLinux`, the efibootmgr label). Whether upstream is fine
   with the name "GoboRefined" and the use of its name is a question for upstream.
8. **GoboHide kernel patch (0.9.3).** `spin/patches/linux-6.12.16-gobohide.patch` is the patch shipped
   by gobolinux/Recipes for Linux 6.12.16 (`01-gobohide.patch`), applied to our 6.12.117 build. GPL-2.0
   with the kernel; original authors Felipe W. Damasio / Lucas C. Villa Real; 6.12 refresh by Samuel
   Dionne-Riel. URL:
   https://github.com/gobolinux/Recipes/blob/master/Linux/6.12.16/01-gobohide.patch
