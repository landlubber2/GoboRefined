#!/bin/bash
# Shared part of the app package builds (apps/<name>/build.sh). Runs as root INSIDE a GoboLinux 017.01
# build root (the lab uses an overlay on top of the system build root, so the system build is not
# touched: /Mount/Scratch/approot.sh in HANDOFF.md). Sources are expected in $SRC (default
# /Data/Apps/src), packages are written to $OUT (default /Data/Apps/out).
#
# A package is GoboLinux's own format, as Settings > Software > Apps installs it:
#   Name--Version--x86_64.tar.bz2  containing  Name/Version/{bin,lib,share,...,Resources}
set -euo pipefail
SRC=${SRC:-/Data/Apps/src}
OUT=${OUT:-/Data/Apps/out}
WORK=${WORK:-/Data/Apps/work}
set +u; [ -f /System/Environment/Cache ] && . /System/Environment/Cache; set -u
export PATH=/System/Index/bin:/System/Index/sbin:$PATH
mkdir -p "$OUT" "$WORK"

# need FILE SHA256: the pinned source must be there and unchanged
need() {
   [ -f "$SRC/$1" ] || { echo "missing source $SRC/$1"; exit 1; }
   echo "$2  $SRC/$1" | sha256sum -c --quiet - || { echo "sha256 of $1 does not match"; exit 1; }
}

# unpack FILE DIR: fresh copy of the source tree in $WORK/DIR, cd into it
unpack() {
   rm -rf "$WORK/$2" && tar xf "$SRC/$1" -C "$WORK" && cd "$WORK/$2"
}

# resources P NAME VERSION SUMMARY LICENSE HOMEPAGE [DEPENDENCY LINES...]
resources() {
   local p=$1 name=$2 version=$3 summary=$4 license=$5 home=$6; shift 6
   mkdir -p "$p/Resources"
   echo x86_64 > "$p/Resources/Architecture"
   printf '%s\n' "$@" > "$p/Resources/Dependencies"
   printf '%s\n' "[Name] $name" "[Version] $version" "[Summary] $summary" "[License] $license" \
      "[Homepage] $home" "[Packager] Gobo Linux Refined, apps/ in https://github.com/landlubber2/GoboRefined" \
      > "$p/Resources/Description"
}

# package NAME VERSION: write $OUT/NAME--VERSION--x86_64.tar.bz2 from /Programs/NAME/VERSION,
# then run the same check Settings runs before installing (gobo-app-check, if this root has it)
package() {
   local name=$1 version=$2 f="$OUT/$1--$2--x86_64.tar.bz2"
   [ -d "/Programs/$name/$version" ] || { echo "no /Programs/$name/$version"; exit 1; }
   find "/Programs/$name/$version" -perm /6000 -type f -exec chmod ug-s {} +
   tar -cjf "$f" --owner=0 --group=0 -C /Programs "$name/$version"
   ls -l "$f"
   sha256sum "$f" | tee "$f.sha256"
   du -sh "/Programs/$name/$version" | sed 's/^/installed size: /'
}
