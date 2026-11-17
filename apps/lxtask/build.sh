#!/bin/bash
# LXTask 0.1.12: a small task manager (LXDE, GPL-2.0-or-later), GTK 3 build.
# Source: https://github.com/lxde/lxtask/archive/refs/tags/0.1.12.tar.gz (the project's own tag).
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/lib.sh"
V=0.1.12 P=/Programs/LXTask/0.1.12
need lxtask-$V.tar.gz f9d97ebdd8402fe7d9533b6173d0f553d5f9987f5c2885f7d2ee070e80300ab3
unpack lxtask-$V.tar.gz lxtask-$V
./autogen.sh > "$WORK/lxtask-autogen.log" 2>&1
./configure --prefix=$P --sysconfdir=$P/Resources/Defaults/Settings --enable-gtk3 > "$WORK/lxtask-configure.log" 2>&1 ||
   { tail -n 30 "$WORK/lxtask-configure.log"; exit 1; }
make -j"$(nproc)" > "$WORK/lxtask-make.log" 2>&1 || { tail -n 30 "$WORK/lxtask-make.log"; exit 1; }
rm -rf $P && make install > "$WORK/lxtask-install.log" 2>&1
# the menu entry: a plain name for people, the system icon theme's task manager icon
d=$P/share/applications/lxtask.desktop
sed -i 's/^Name=.*/Name=Task Manager/; s/^Icon=.*/Icon=utilities-system-monitor/' "$d"
grep -q '^Keywords=' "$d" || echo 'Keywords=task;process;cpu;memory;kill;end;' >> "$d"
resources $P LXTask $V "Task manager: what is using the processor and memory, and ending a program" \
   GPL-2.0-or-later https://github.com/lxde/lxtask "GTK+ >= 3.20"
package LXTask $V
