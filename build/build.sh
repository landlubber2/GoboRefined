#!/bin/bash
# build/build.sh — build the GoboRefined ISO and update file from this repository.
#
# Run as root on GoboLinux 017.01 (the stock live session or a stock install), from a checkout
# of this repository, with WORK pointing at a folder on a disk with enough free space:
#
#   WORK=/Mount/Build bash build/build.sh            (everything; same as "all")
#
# Commands:  check | fetch | programs | image | all | unmount
#   check     prerequisites only
#   fetch     find/download and verify the stock ISO and every source in build/sources.manifest
#   programs  build the added programs (spin/build-programs.sh steps) in a build root
#   image     make the ISO and update file (spin/build-iso.sh)
#   unmount   undo the mounts a stopped run left behind
#
# Environment:
#   WORK               work folder (absolute, no spaces)            [/Data/Build/GoboRefined]
#   ISO                the stock GoboLinux-017.01-x86_64.iso, a file or a DVD device. If unset:
#                      $WORK/sources, then the DVD drive (/dev/sr0), else it is downloaded.
#   VERSION            version written into the image                [spin/build-iso.sh default]
#   GOBO_SIGNING_KEY   private key (PEM) to sign the update file with. Read into memory only
#                      (a copy in /dev/shm, deleted after use); never copied into the image.
#                      If unset, a key pair is generated once in $WORK/keys and reused.
#   REBUILD            program steps to build again even if done, e.g. REBUILD="libfm pcmanfm"
#
# The script is restartable: downloads, finished program steps and the build root are kept in
# WORK; a later run skips what is done and still valid (a step is redone when its part of
# spin/build-programs.sh, its sources or its repository files change). See BUILDING.md.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
MANIFEST=$HERE/sources.manifest
WORK=${WORK:-/Data/Build/GoboRefined}
CMD=${1:-all}

STOCK_VERSION=017.01
STOCK_ISO_SIZE=2433744896          # bytes of GoboLinux-017.01-x86_64.iso
KVER=$(head -n 1 "$REPO/spin/kernel-version")   # the image's kernel (0.9.1: one place for the version)
KREL=$KVER-Gobo
# 0.9.1: + linux (before rtl8852au, which is built against it), intel-microcode, firefox, ca-bundle
STEPS="xorriso xrandr inter jetbrains-mono papirus menu-cache libfm pcmanfm pavucontrol lxrandr
       lxdm udevil usb-modeswitch linux rtl8852au onlyoffice copyq gobofiles l3afpad dnsmasq linux-firmware sof-firmware
       sbc pulseaudio-bluetooth intel-microcode firefox ca-bundle"
LAST_STEP=ca-bundle

say() { echo "== $*"; }
die() { echo "build.sh: ERROR: $*" >&2; exit 1; }

case "$CMD" in
   check|fetch|programs|image|all|unmount) ;;
   -h|--help|help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
   *) die "unknown command '$CMD' (check, fetch, programs, image, all, unmount)" ;;
esac

[ "$(id -u)" = 0 ] || die "run as root (sudo bash build/build.sh)"
[[ "$WORK" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "WORK must be an absolute path without spaces (got '$WORK')"
[ "$(awk '$1 == "linux" { print $2 }' "$MANIFEST")" = "$KVER" ] ||
   die "spin/kernel-version says $KVER, build/sources.manifest pins another kernel (change both)"
[ -f "$MANIFEST" ] && [ -f "$REPO/spin/build-iso.sh" ] && [ -f "$REPO/spin/build-programs.sh" ] ||
   die "$REPO does not look like a GoboRefined checkout"
case "$WORK/" in "$REPO"/*) die "WORK must not be inside the repository checkout" ;; esac

SRCDIR=$WORK/sources
STATE=$WORK/state
BR=$WORK/buildroot/root           # the build root: overlay over the stock image
IMG=$WORK/image
OUTDIR=$WORK/output
mkdir -p "$WORK" "$SRCDIR" "$STATE" "$WORK/logs" "$OUTDIR"

# one run at a time
exec 9> "$WORK/.lock"
flock -n 9 || die "another build.sh is running with WORK=$WORK"

LOG=$WORK/logs/build-$(date +%Y%m%d-%H%M%S)-$CMD.log
exec > >(tee -a "$LOG") 2>&1
START=$(date +%s)
echo "GoboRefined build ($CMD), $(date -u +%Y-%m-%dT%H:%M:%SZ); repository $REPO; work folder $WORK; log $LOG"

########## mounts ##########################################################################

# every mount point below $WORK, deepest first
unmount_all() {
   local m
   awk -v w="$WORK/" 'index($2, w) == 1 { print $2 }' /proc/mounts | sort -r | while read -r m
   do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || echo "could not unmount $m"
   done
}
TMPKEY=
on_exit() {
   local rc=$?
   set +e
   [ -n "$TMPKEY" ] && rm -f "$TMPKEY"
   unmount_all
   if [ $rc -ne 0 ]
   then echo "build.sh: stopped with an error (exit $rc). Fix it and run the same command again: finished parts are kept. Log: $LOG"
   fi
   exit $rc
}
trap on_exit EXIT

if [ "$CMD" = unmount ]
then unmount_all; say "nothing of this build is mounted any more"; exit 0
fi

########## prerequisites ###################################################################

check_prereqs() {
   say "checking prerequisites"
   local missing=() t need_gb free_kb mem_mb fs
   if [ "$(cat /System/Settings/GoboLinuxVersion 2>/dev/null)" != "$STOCK_VERSION" ]
   then missing+=("GoboLinux $STOCK_VERSION (this system says: '$(cat /System/Settings/GoboLinuxVersion 2>/dev/null || echo not GoboLinux)')")
   fi
   [ "$(uname -m)" = x86_64 ] || missing+=("an x86_64 machine")
   for t in wget sha256sum mount umount chroot mksquashfs openssl tar xz bzip2 unzip gcc make \
            luac lsinitrd flock awk sed grep cmp truncate stat df blockdev mountpoint
   do command -v $t > /dev/null || missing+=("the command '$t'")
   done
   for t in overlay squashfs loop
   do modprobe $t 2> /dev/null || true
   done
   grep -qw overlay /proc/filesystems || missing+=("overlay file system support in the kernel")
   grep -qw squashfs /proc/filesystems || missing+=("squashfs support in the kernel")
   # free space (first run: sources + build root + image; later runs: the image part)
   fs=$(stat -f -c %T "$WORK")
   case "$fs" in tmpfs|overlay|overlayfs|ramfs) missing+=("WORK on a real disk ($WORK is on '$fs', i.e. in memory; in the live session mount a scratch disk and set WORK to a folder on it)") ;; esac
   if [ -e "$STATE/step-dnsmasq.done" ]; then need_gb=20; else need_gb=30; fi
   free_kb=$(df -Pk "$WORK" | awk 'NR==2 { print $4 }')
   [ "$free_kb" -ge $((need_gb * 1024 * 1024)) ] ||
      missing+=("$need_gb GB free in $WORK (there are $((free_kb / 1024 / 1024)) GB)")
   # a clock far behind breaks make (files "in the future") and TLS downloads
   if [ -n "$(find "$REPO" -maxdepth 2 -newermt 'now + 1 hour' 2> /dev/null | head -n 1)" ]
   then missing+=("a correct clock (files of the checkout are dated in the future; set it, e.g. date -u -s 'YYYY-MM-DD HH:MM:SS')")
   fi
   mem_mb=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
   [ "$mem_mb" -ge 1800 ] || missing+=("at least 2 GB of RAM (there are $mem_mb MB)")
   if [ ${#missing[@]} -gt 0 ]
   then
      echo "Missing:"
      printf '  - %s\n' "${missing[@]}"
      die "prerequisites not met"
   fi
   echo "ok: GoboLinux $STOCK_VERSION, $((free_kb / 1024 / 1024)) GB free in $WORK ($fs), $mem_mb MB RAM"
}

########## downloads #######################################################################

# manifest_line <step>: the manifest lines of a step
manifest_lines() { awk -v s="$1" '$1 == s' "$MANIFEST"; }

need_network() {
   wget -q --spider --timeout=20 https://github.com/ ||
      die "no internet access (wget https://github.com/ failed). In the live session: dhcpcd -b <interface>, e.g. dhcpcd -b enp0s3"
}

# fetch_file <file> <sha256> <url>
fetch_file() {
   local f=$1 sum=$2 url=$3 got
   if [ -f "$SRCDIR/$f" ]
   then
      [ "$(sha256sum < "$SRCDIR/$f" | cut -d' ' -f1)" = "$sum" ] && { echo "ok      $f"; return 0; }
      echo "bad     $f (sha256 differs, downloading again)"
      rm -f "$SRCDIR/$f"
   fi
   echo "get     $f  <- $url"
   wget -nv -c --timeout=60 --tries=10 --retry-connrefused -O "$SRCDIR/$f.part" "$url" || die "download failed: $url"
   got=$(sha256sum < "$SRCDIR/$f.part" | cut -d' ' -f1)
   if [ "$got" != "$sum" ]
   then
      rm -f "$SRCDIR/$f.part"
      die "$f: sha256 is $got, the manifest pins $sum. Not used. (Upstream changed the file, or the download was damaged.)"
   fi
   mv "$SRCDIR/$f.part" "$SRCDIR/$f"
   echo "ok      $f"
}

fetch_sources() {
   say "sources (pinned in build/sources.manifest)"
   local step ver file sum lic url missing=0
   while read -r step ver file sum lic url
   do [ "$step" = iso ] || [ -f "$SRCDIR/$file" ] || missing=1
   done < <(grep -v -e '^#' -e '^[[:space:]]*$' "$MANIFEST")
   [ $missing = 0 ] || need_network
   while read -r step ver file sum lic url
   do
      [ "$step" = iso ] && continue
      [ -n "$url" ] || die "bad manifest line for $step"
      fetch_file "$file" "$sum" "$url"
   done < <(grep -v -e '^#' -e '^[[:space:]]*$' "$MANIFEST")
}

# iso_ok <file or device>: first STOCK_ISO_SIZE bytes have the pinned sha256
iso_ok() {
   local f=$1 size sum
   sum=$(manifest_lines iso | awk '{ print $4 }')
   if [ -b "$f" ]
   then size=$(blockdev --getsize64 "$f" 2> /dev/null || echo 0)
   else size=$(stat -c %s "$f")
   fi
   [ "$size" -ge "$STOCK_ISO_SIZE" ] || return 1
   [ -b "$f" ] || [ "$size" -eq "$STOCK_ISO_SIZE" ] || return 1
   echo "checking the sha256 of $f (about a minute)"
   [ "$(head -c "$STOCK_ISO_SIZE" "$f" | sha256sum | cut -d' ' -f1)" = "$sum" ]
}

resolve_iso() {
   say "stock ISO (GoboLinux $STOCK_VERSION)"
   local file sum url stamp
   file=$(manifest_lines iso | awk '{ print $3 }')
   sum=$(manifest_lines iso | awk '{ print $4 }')
   url=$(manifest_lines iso | awk '{ print $6 }')
   if [ -n "${ISO:-}" ]
   then
      [ -e "$ISO" ] || die "ISO=$ISO does not exist"
   elif [ -f "$SRCDIR/$file" ]
   then ISO=$SRCDIR/$file
   elif [ -b /dev/sr0 ] && iso_ok /dev/sr0
   then ISO=/dev/sr0; echo "using the stock ISO in the DVD drive (/dev/sr0)"; return 0
   else
      need_network
      echo "downloading $url (2.4 GB)"
      fetch_file "$file" "$sum" "$url"
      ISO=$SRCDIR/$file
   fi
   # a file that was checked before (same size and time) is not hashed again
   if [ -f "$ISO" ]
   then
      stamp="$(readlink -f "$ISO") $(stat -c '%s %Y' "$ISO") $sum"
      if [ "$(cat "$STATE/iso.ok" 2>/dev/null)" = "$stamp" ]
      then echo "ok      $ISO (checked before)"; return 0
      fi
   fi
   iso_ok "$ISO" || die "$ISO is not the stock GoboLinux-017.01-x86_64.iso (size or sha256 differs; pinned sha256 $sum)"
   [ -f "$ISO" ] && echo "$stamp" > "$STATE/iso.ok"
   echo "ok      $ISO"
}

mount_stock() {
   mountpoint -q "$WORK/mnt/stock" && return 0
   mkdir -p "$WORK/mnt/iso" "$WORK/mnt/stock"
   mountpoint -q "$WORK/mnt/iso" || mount -o ro "$ISO" "$WORK/mnt/iso" || die "cannot mount $ISO"
   [ -f "$WORK/mnt/iso/gobolinux-live.squashfs" ] || die "$ISO has no gobolinux-live.squashfs"
   mount -t squashfs -o ro,loop "$WORK/mnt/iso/gobolinux-live.squashfs" "$WORK/mnt/stock" ||
      die "cannot mount the stock live image"
   [ -d "$WORK/mnt/stock/Programs/LiveCD" ] || die "the stock live image looks wrong"
}

########## build root and programs #########################################################

mount_buildroot() {
   mount_stock
   mountpoint -q "$BR" && return 0
   mkdir -p "$WORK/buildroot/upper" "$WORK/buildroot/work" "$BR"
   mount -t overlay overlay \
      -o "lowerdir=$WORK/mnt/stock,upperdir=$WORK/buildroot/upper,workdir=$WORK/buildroot/work" "$BR" ||
      die "cannot mount the build root overlay"
}

bind_buildroot() {
   local pair mp
   for pair in Status:/proc Objects:/sys Devices:/dev
   do
      mp=$BR/System/Kernel/${pair%%:*}
      mountpoint -q "$mp" && continue
      mount --rbind "${pair#*:}" "$mp"
      mount --make-rslave "$mp"
   done
   mkdir -p "$BR/Data/Build/repo" "$BR/Data/Build/src" "$BR/Data/Build/work"
   if ! mountpoint -q "$BR/Data/Build/repo"
   then mount --bind "$REPO" "$BR/Data/Build/repo" && mount -o remount,bind,ro "$BR/Data/Build/repo"
   fi
   if ! mountpoint -q "$BR/Data/Build/src"
   then mount --bind "$SRCDIR" "$BR/Data/Build/src" && mount -o remount,bind,ro "$BR/Data/Build/src"
   fi
}

# step_inputs <step>: everything a step depends on (its hash decides whether it is redone)
step_inputs() {
   local s=$1 bp=$REPO/spin/build-programs.sh
   sed -n '1,/^case "\$1" in$/p' "$bp"
   awk -v s="$s)" '$0 == s { p = 1 } p { print } p && /^   ;;$/ { exit }' "$bp"
   manifest_lines "$s"
   case "$s" in
      menu-cache) manifest_lines libfm ;;
      libfm)      cat "$REPO/spin/patches/libfm-1.2.5-gobo.patch" ;;
      pcmanfm)    cat "$REPO/spin/patches/pcmanfm-1.2.5-gobo.patch" ;;
      udevil)     cat "$REPO/spin/patches/udevil-0.4.4-gobo-monitor.patch" ;;
      usb-modeswitch) cat "$REPO/spin/gobo-wifi-switch" ;;
      linux|rtl8852au) cat "$REPO/spin/kernel-version" ;;
      lxdm)       find "$REPO/spin/lxdm" -type f | LC_ALL=C sort | xargs cat ;;
      gobofiles)  find "$REPO/spin/gobofiles" -type f | LC_ALL=C sort | xargs cat ;;
   esac
}

run_step() {
   local s=$1 slog=$WORK/logs/step-$s.log
   rm -rf "$BR/Data/Build/work" && mkdir -p "$BR/Data/Build/work"
   # a clean environment plus GoboLinux's own environment cache (as a root login has it)
   if ! chroot "$BR" /usr/bin/env -i HOME=/Users/root USER=root LOGNAME=root TERM=dumb SHELL=/bin/bash \
         PATH=/System/Index/bin:/System/Index/sbin:/bin:/usr/bin \
         SRC=/Data/Build/src WORK=/Data/Build/work SPIN=/Data/Build/repo/spin \
         /bin/bash -c '[ -f /System/Environment/Cache ] && . /System/Environment/Cache; cd /Data/Build/work &&
                       exec bash /Data/Build/repo/spin/build-programs.sh "$1"' step "$s" > "$slog" 2>&1
   then
      tail -n 25 "$slog"
      die "program step '$s' failed (full log: $slog)"
   fi
   grep -q "^STEP-DONE $s\$" "$slog" || die "program step '$s' did not finish (log: $slog)"
   rm -rf "$BR/Data/Build/work" && mkdir -p "$BR/Data/Build/work"
}

build_programs() {
   say "programs (spin/build-programs.sh, inside the build root $BR)"
   mount_buildroot
   bind_buildroot
   local s h t0 force=" ${REBUILD:-} "
   for s in $STEPS
   do
      h=$(step_inputs "$s" | sha256sum | cut -d' ' -f1)
      if [ "$(cat "$STATE/step-$s.done" 2>/dev/null)" = "$h" ] && [[ "$force" != *" $s "* ]]
      then echo "done    $s"; continue
      fi
      # LibFM is built "extra only" by menu-cache, PCManFM links against LibFM: redo what follows
      case "$s" in
         menu-cache) rm -f "$STATE/step-libfm.done" "$STATE/step-pcmanfm.done" ;;
         linux)      rm -f "$STATE/step-rtl8852au.done" ;;   # the driver is built against it
         libfm)      rm -f "$STATE/step-pcmanfm.done" ;;
      esac
      rm -f "$STATE/step-$s.done"
      t0=$(date +%s)
      echo "build   $s ..."
      run_step "$s"
      echo "$h" > "$STATE/step-$s.done"
      echo "done    $s ($(( $(date +%s) - t0 )) s)"
   done
   [ -x "$BR/Data/Build/xorriso-inst/bin/xorriso" ] || die "xorriso was not built"
}

########## image ###########################################################################

default_version() {
   sed -n 's/^VERSION=\${VERSION:-\([0-9A-Za-z.-]*\)}$/\1/p' "$REPO/spin/build-iso.sh" | head -n 1
}

prepare_key() {
   say "update signing key"
   local projpub=$REPO/spin/ab/update-signing.pub.pem
   TMPKEY=$(umask 077; mktemp /dev/shm/gobo-build-key.XXXXXXXX)
   if [ -n "${GOBO_SIGNING_KEY:-}" ]
   then
      [ -r "$GOBO_SIGNING_KEY" ] || die "GOBO_SIGNING_KEY=$GOBO_SIGNING_KEY cannot be read"
      cat "$GOBO_SIGNING_KEY" > "$TMPKEY"
      KEY_FROM="your key (GOBO_SIGNING_KEY)"
   else
      if [ ! -s "$WORK/keys/update-signing.pem" ]
      then
         (umask 077; mkdir -p "$WORK/keys"
          openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$WORK/keys/update-signing.pem" 2> /dev/null) ||
            die "could not generate a key pair"
         echo "generated a new key pair: $WORK/keys/update-signing.pem (private, mode 600)"
      fi
      cat "$WORK/keys/update-signing.pem" > "$TMPKEY"
      KEY_FROM="the key generated for this work folder ($WORK/keys/update-signing.pem)"
   fi
   openssl pkey -in "$TMPKEY" -noout 2> /dev/null || die "the signing key is not a private key openssl can read"
   openssl pkey -in "$TMPKEY" -pubout -out "$IMG/update-signing.pub.pem" 2> /dev/null
   if cmp -s <(tr -d '\r' < "$projpub") "$IMG/update-signing.pub.pem"
   then KEY_PROJECT=yes
   else KEY_PROJECT=no
   fi
   echo "signing with $KEY_FROM; project key: $KEY_PROJECT"
}

build_image() {
   local v=${VERSION:-$(default_version)}
   [[ "$v" =~ ^[0-9A-Za-z.-]+$ ]] || die "bad VERSION '$v'"
   say "image GoboRefined $v (spin/build-iso.sh)"
   mount_buildroot
   [ -x "$BR/Data/Build/xorriso-inst/bin/xorriso" ] && [ -e "$STATE/step-$LAST_STEP.done" ] ||
      die "the programs are not built yet (run: build.sh programs)"
   # a fresh copy-on-write layer over the stock image every time
   mountpoint -q "$IMG/rootfs" && umount -R "$IMG/rootfs"
   ! grep -q " $IMG/" /proc/mounts || die "something is still mounted below $IMG (run: build.sh unmount)"
   rm -rf "$IMG"
   mkdir -p "$IMG/upper" "$IMG/ovl-work" "$IMG/rootfs"
   mount -t overlay overlay -o "lowerdir=$WORK/mnt/stock,upperdir=$IMG/upper,workdir=$IMG/ovl-work" "$IMG/rootfs" ||
      die "cannot mount the image overlay"
   prepare_key
   B=$IMG R=$IMG/rootfs REPO=$REPO PROGRAMS_FROM=$BR ISO=$ISO VERSION=$v \
      XORRISO=$BR/Data/Build/xorriso-inst/bin/xorriso SIGNING_KEY=$TMPKEY PUBKEY=$IMG/update-signing.pub.pem \
      bash "$REPO/spin/build-iso.sh"
   rm -f "$TMPKEY"; TMPKEY=
   grep -q " $IMG/rootfs/" /proc/mounts && die "build-iso.sh left mounts inside the image tree"
   local n=GoboRefined-$v
   rm -f "$OUTDIR/$n".*
   mv "$IMG/$n.iso" "$IMG/$n.update" "$OUTDIR/"
   cp "$IMG/update-signing.pub.pem" "$OUTDIR/$n.update-signing.pub.pem"
   (cd "$OUTDIR" && sha256sum "$n.iso" > "$n.iso.sha256" && sha256sum "$n.update" > "$n.update.sha256")
   # the big intermediate files are not needed any more (logs stay in $IMG)
   umount "$IMG/rootfs"
   rm -rf "$IMG/upper" "$IMG/ovl-work" "$IMG/gobolinux-live.squashfs"
   cp "$LOG" "$OUTDIR/$n.build.log"
   say "done"
   ls -l "$OUTDIR"
   cat "$OUTDIR/$n.iso.sha256" "$OUTDIR/$n.update.sha256"
   echo
   if [ "$KEY_PROJECT" = yes ]
   then echo "The update file is signed with the project's key: it applies to every GoboRefined install."
   else
      echo "NOTE: the update file is signed with $KEY_FROM."
      echo "      Systems installed from THIS build's ISO accept updates signed with that key only;"
      echo "      official GoboRefined installs will refuse this update file, and this build's"
      echo "      systems will refuse official update files. Keep the private key to sign later"
      echo "      updates (GOBO_SIGNING_KEY=...). Its public key: $OUTDIR/$n.update-signing.pub.pem"
   fi
}

########## main ############################################################################

check_prereqs
case "$CMD" in
   check)    [ -e "$STATE/iso.ok" ] || echo "(the stock ISO is checked by 'fetch')" ;;
   fetch)    resolve_iso; fetch_sources ;;
   programs) resolve_iso; fetch_sources; build_programs ;;
   image)    resolve_iso; build_image ;;
   all)      resolve_iso; fetch_sources; build_programs; build_image ;;
esac
T=$(( $(date +%s) - START ))
say "finished '$CMD' in $((T / 60)) min $((T % 60)) s; disk use in $WORK:"
{ du -shx "$WORK"/* "$WORK/buildroot/upper" 2> /dev/null || true; } | sed 's/^/   /'
df -h "$WORK" | sed 's/^/   /'
exit 0
