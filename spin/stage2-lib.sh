#!/bin/bash
# spin/stage2-lib.sh: helpers for the stage-2 steps of spin/build-programs.sh (sourced by them).
# Stage-2 steps run in build/build.sh's stage-2 build root: an overlay over the stage-1 build root
# whose C library was switched to Glibc 2.38 (spin/glibc-switch.sh), so current prebuilt tools run.
# Kept apart from the header of build-programs.sh on purpose: that header is part of every step's
# hash, a change there would rebuild every stage-1 step. This file is part of every stage-2 step's hash.

# stage2_check: stop unless this is the stage-2 root (C library 2.38)
stage2_check() {
   [ "$(getconf GNU_LIBC_VERSION)" = "glibc 2.38" ] && [ "$(readlink /Programs/Glibc/Current)" = 2.38 ] ||
      { echo "this step belongs to stage 2 (glibc 2.38 build root); here: $(getconf GNU_LIBC_VERSION)"; exit 1; }
}

# stage2_unlink <target prefix>: remove the index links that point below <target prefix> (e.g.
# /Programs/LLVM/9.0.1/ or /System/Aliens/PIP/3.8/bin/meson), so SymlinkProgram (whose default is to
# keep links that exist) links the new program. Listed first, then deleted (an overlay walk).
stage2_unlink() {
   local t=$1 list
   case "$t" in /Programs/?*|/System/Aliens/?*) ;; *) echo "stage2_unlink: bad target '$t'"; exit 1 ;; esac
   list=$(mktemp)
   find /System/Index -xdev -lname "$t*" -print0 > "$list"
   echo "index links into $t: $(tr -cd '\0' < "$list" | wc -c)"
   xargs -0 -r rm -f < "$list"
   rm -f "$list"
}

# stage2_resources <Name> <Version> <Summary> <Licence> <Homepage> <Source URL> [<dependency>...]
stage2_resources() {
   local name=$1 ver=$2 sum=$3 lic=$4 home=$5 url=$6 P=/Programs/$1/$2
   shift 6
   mkdir -p $P/Resources
   echo x86_64 > $P/Resources/Architecture
   if [ $# -gt 0 ]; then printf '%s\n' "$@"; else :; fi > $P/Resources/Dependencies
   printf '[Name] %s\n[Summary] %s\n[License] %s\n[Homepage] %s\n' "$name" "$sum" "$lic" "$home" > $P/Resources/Description
   echo "[File] $url" > $P/Resources/PackageSource
   echo "built in the stage-2 build root (glibc 2.38) of GoboRefined's build/build.sh; build root only" > $P/Resources/GoboRefinedStage
   chown -R root:root $P
}
