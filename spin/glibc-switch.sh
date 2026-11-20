#!/bin/bash
# spin/glibc-switch.sh <root> <programs-from> <tmpdir>
#
# Make Glibc 2.38 (build step glibc) the C library of the system tree <root>, in place of the stock
# 017.01's 2.30, which stays in /Programs/Glibc/2.30 with nothing linked to it. Shared by
#   - spin/build-iso.sh: the image (<programs-from> = the stage-1 build root holding /Programs/Glibc/2.38),
#   - build/build.sh: the stage-2 build root (<programs-from> = that root itself: 2.38 is already in it).
# <tmpdir> gets the lists glibc-gone, glibc-gone-users, glibc-old-links. Run as root; /proc must be
# mounted in <root> (chroot commands below run in it). Exits non-zero on any failed check.
set -e
[ $# = 3 ] || { echo "usage: glibc-switch.sh <root> <programs-from> <tmpdir>"; exit 1; }
R=$1 PROGRAMS_FROM=$2 B=$3
[ -d "$R/Programs/LiveCD" ] && [ -d "$R/System/Index" ] || { echo "glibc-switch: $R is not a GoboLinux 017.01 tree"; exit 1; }
[ -n "$PROGRAMS_FROM" ] && [ -d "$PROGRAMS_FROM/Programs" ] || { echo "glibc-switch: no programs folder in '$PROGRAMS_FROM'"; exit 1; }
[ -d "$B" ] && [ -w "$B" ] || { echo "glibc-switch: $B is not a writable folder"; exit 1; }
# 0.9.7: the C library 2.38 (build step glibc) becomes the system's; the stock 2.30 stays in
# /Programs/Glibc/2.30 with nothing linked to it. The index is switched from THIS machine, not
# inside the chroot: until the loader and libc.so.6 links point at one version, nothing may run in
# the tree. After that every chroot command (SymlinkProgram, ldconfig, depmod, dracut,
# gobo-make-system's ProfileInstall) runs on 2.38.
GV=2.38 GOLDV=2.30
GSRC="$PROGRAMS_FROM/Programs/Glibc/$GV"
[ -x "$GSRC/lib/ld-linux-x86-64.so.2" ] && [ -f "$GSRC/lib/libc.so.6" ] && [ -f "$GSRC/lib/libcrypt.so.1" ] &&
   [ -s "$GSRC/lib/locale/locale-archive" ] || { echo "Glibc $GV not built (step glibc; no $GSRC)"; exit 1; }
[ "$(readlink $R/Programs/Glibc/Current)" = "$GOLDV" ] && [ -d $R/Programs/Glibc/$GOLDV/lib ] || { echo "the image's C library is not the stock $GOLDV"; exit 1; }
echo "== C library: Glibc $GOLDV -> $GV"
if [ "$(readlink -f "$GSRC")" != "$(readlink -f "$R/Programs/Glibc/$GV" 2>/dev/null)" ]
then rm -rf $R/Programs/Glibc/$GV && cp -a "$GSRC" $R/Programs/Glibc/
else echo "Glibc $GV is already in $R (from its lower layer): not copied"
fi
# libraries 2.30 had and 2.38 has not (e.g. libSegFault.so): nothing in the image may need them
for f in $R/Programs/Glibc/$GOLDV/lib/*.so.*
do
   b=$(basename "$f")
   case "$b" in *-$GOLDV.so|*-1.0.so) continue ;; esac   # the versioned file names behind the links
   [ -e "$R/Programs/Glibc/$GV/lib/$b" ] || echo "$b"
done > $B/glibc-gone
if [ -s $B/glibc-gone ]
then
   echo "sonames of $GOLDV not in $GV: $(tr '\n' ' ' < $B/glibc-gone)"
   find $R/Programs -path "$R/Programs/Glibc" -prune -o -type f \( -perm -u+x -o -name '*.so*' \) -print0 |
      xargs -0 -r readelf -d 2> /dev/null | awk '/^File: / { f = $2 } /\(NEEDED\)/ { gsub(/[\[\]]/, "", $5); print $5 "\t" f }' |
      grep -F -f <(sed 's/.*/&\t/' $B/glibc-gone) > $B/glibc-gone-users || true
   [ ! -s $B/glibc-gone-users ] || { echo "programs need libraries that $GV does not have:"; head -n 20 $B/glibc-gone-users; exit 1; }
fi
# every index link into 2.30 goes (listed first, then deleted: an overlay walk), then 2.38's lib/ and
# bin/ are linked by hand: loader, libc.so.6 & co. switch in one go
find $R/System -xdev -lname "/Programs/Glibc/$GOLDV/*" -print0 > $B/glibc-old-links
echo "index links into Glibc $GOLDV: $(tr -cd '\0' < $B/glibc-old-links | wc -c)"
xargs -0 -r rm -f < $B/glibc-old-links
for sub in lib bin
do
   for f in $R/Programs/Glibc/$GV/$sub/*
   do
      b=$(basename "$f") dst=$R/System/Index/$sub/$(basename "$f")
      if [ ! -L "$dst" ] && [ ! -e "$dst" ]
      then ln -s "/Programs/Glibc/$GV/$sub/$b" "$dst"
      else echo "kept (another program's, or a real folder): $sub/$b -> $(readlink "$dst")"
      fi
   done
done
ln -sfn $GV $R/Programs/Glibc/Current
[ "$(chroot $R readlink -f /lib64/ld-linux-x86-64.so.2)" = "/Programs/Glibc/$GV/lib/ld-linux-x86-64.so.2" ] &&
   [ "$(chroot $R readlink -f /System/Index/lib/libc.so.6)" = "/Programs/Glibc/$GV/lib/libc.so.6" ] ||
   { echo "loader or libc.so.6 do not point at Glibc $GV"; exit 1; }
chroot $R /bin/true || { echo "the image does not run programs on Glibc $GV"; exit 1; }
chroot $R SymlinkProgram Glibc $GV | tail -n 1
chroot $R ldconfig
left=$(find $R/System -xdev -lname "/Programs/Glibc/$GOLDV/*" | head -n 5)
[ -z "$left" ] || { echo "links into Glibc $GOLDV left: $left"; exit 1; }
chroot $R ldd --version | head -n 1 | grep -q " $GV\$" || { chroot $R ldd --version | head -n 1; echo "ldd is not $GV"; exit 1; }
chroot $R getconf GNU_LIBC_VERSION | grep -qx "glibc $GV" || { echo "getconf does not report glibc $GV"; exit 1; }
[ "$(chroot $R readlink -f /System/Index/include/stdio.h)" = "/Programs/Glibc/$GV/include/stdio.h" ] || { echo "headers are not $GV's"; exit 1; }
# logins: libcrypt 2.38 makes the same SHA-512 hash as openssl (as the installer writes them)
h_new=$(chroot $R python3 -c 'import crypt; print(crypt.crypt("Gobo test 1", "$6$gobosalt1234567"))')
h_ref=$(chroot $R openssl passwd -6 -salt gobosalt1234567 'Gobo test 1')
[ -n "$h_ref" ] && [ "$h_new" = "$h_ref" ] || { echo "libcrypt in the image gives another hash"; exit 1; }
chroot $R locale -a | grep -qx pl_PL.utf8 && chroot $R locale -a | grep -qx en_US.utf8 || { echo "locales missing"; exit 1; }
chroot $R env LC_ALL=pl_PL.UTF-8 date -d 2026-11-18 +%A | grep -qx 'środa' || { echo "Polish locale does not work"; exit 1; }
echo "Glibc $GV: $(chroot $R ldd --version | head -n 1); $(chroot $R locale -a | wc -l) locales"
