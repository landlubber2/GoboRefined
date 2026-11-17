#!/bin/bash
# Qalculate! 5.13 (GTK 3): a calculator for everything from 2+2 to units, currencies and equations
# (GPL-2.0-or-later). One package: the library libqalculate 5.13.2 and the program qalculate-gtk 5.13.0
# both live in /Programs/Qalculate-GTK/5.13.0 (the program finds the library through its RUNPATH), so
# Settings > Apps installs it as one file.
# Sources: the projects' own release tarballs on GitHub (Qalculate/libqalculate, Qalculate/qalculate-gtk).
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/lib.sh"
LV=5.13.2 V=5.13.0 P=/Programs/Qalculate-GTK/5.13.0
need libqalculate-$LV.tar.gz 81af6c54018d5cbc9ce4df5a82c3ffb7b195193d72dcabb904f522b69936f3e6
need qalculate-gtk-$V.tar.gz 2c6c9711fcd1bebb09b27c39dda9bd6e0a86b1b17b1538b4e9a1c711e435a830
rm -rf $P
export LDFLAGS="-Wl,-rpath,$P/lib"
export PKG_CONFIG_PATH=$P/lib/pkgconfig

unpack libqalculate-$LV.tar.gz libqalculate-$LV
./configure --prefix=$P --disable-static --without-gnuplot-call > "$WORK/libqalculate-configure.log" 2>&1 ||
   { tail -n 30 "$WORK/libqalculate-configure.log"; exit 1; }
make -j"$(nproc)" > "$WORK/libqalculate-make.log" 2>&1 || { grep -m 5 -B 3 'error' "$WORK/libqalculate-make.log"; tail -n 20 "$WORK/libqalculate-make.log"; exit 1; }
make install > "$WORK/libqalculate-install.log" 2>&1

unpack qalculate-gtk-$V.tar.gz qalculate-gtk-$V
./configure --prefix=$P > "$WORK/qalculate-gtk-configure.log" 2>&1 ||
   { tail -n 30 "$WORK/qalculate-gtk-configure.log"; exit 1; }
make -j"$(nproc)" > "$WORK/qalculate-gtk-make.log" 2>&1 || { grep -m 5 -B 3 'error' "$WORK/qalculate-gtk-make.log"; tail -n 20 "$WORK/qalculate-gtk-make.log"; exit 1; }
make install > "$WORK/qalculate-gtk-install.log" 2>&1

# a calculator does not need the developer files of its library
rm -rf $P/include $P/lib/pkgconfig $P/lib/*.la
strip --strip-unneeded $P/bin/* $P/lib/*.so.* 2>/dev/null || true
d=$(ls $P/share/applications/*.desktop | head -n 1)
grep -q '^Keywords=' "$d" || echo 'Keywords=calculator;calc;math;units;currency;' >> "$d"
resources $P Qalculate-GTK $V "Calculator: arithmetic, units, currencies, equations, plots" \
   GPL-2.0-or-later https://qalculate.github.io "GTK+ >= 3.22"
package Qalculate-GTK $V
