# Making an app package for GoboRefined

GoboRefined installs extra programs from a **package file** in **Settings > Software > Apps**. The page
checks the file first and installs it only if it fits the system. This page tells you how to make such a
file so it passes that check.

You can also ship a program as an **AppImage** (one file, made executable, started with a double-click).
That needs no package at all. Use a package when you want the program to show up in the menu and the
search like a built-in one, and to be removable from the Apps page.
Since 0.10.6 a user can also right-click an AppImage in the file manager and choose **Install**: it moves to
`~/Applications/<Name>/` and gets a start menu entry and/or a pin (name, icon and category come from the
AppImage's own `.desktop` file and icon, so ship those inside it); the start menu editor removes it again.

## The format in one minute

It is GoboLinux's own binary package format (what GoboLinux's `CreatePackage` makes and `InstallPackage`
installs), unchanged:

    LXTask--0.1.12--x86_64.tar.bz2
    └── LXTask/
        └── 0.1.12/
            ├── bin/            commands (lxtask)
            ├── lib/            the program's own libraries, if any
            ├── share/
            │   ├── applications/lxtask.desktop     the menu entry
            │   └── icons/ ...                      icons, if the program has its own
            └── Resources/
                ├── Architecture     one line: x86_64
                ├── Dependencies     one program per line, e.g.  GTK+ >= 3.20
                └── Description      [Name] / [Version] / [Summary] / [License] / [Homepage] lines

When it is installed, the folder becomes `/Programs/LXTask/0.1.12` and its files are linked into the
system (`SymlinkProgram`). Programs installed from the Apps page are kept on the data partition, so they
**stay through system updates and rollbacks**.

## The rules the check applies

These are exactly what [`spin/settings/gobo-app-check`](../spin/settings/gobo-app-check) tests. You can run
that script yourself on GoboRefined: `gobo-app-check MyApp--1.0--x86_64.tar.bz2`. It prints `OK`, `WARN`
or `FAIL` lines and ends with `RESULT compatible` or `RESULT not compatible`. Nothing in the package
is run during the check.

1. **File name:** `Name--Version--Architecture.tar.EXT`
   - Name: letters, digits, `+ _ .`, single dashes between parts (`Qalculate-GTK`). Version: starts with a
     letter or digit (`5.13.0`, `1.1`). An optional revision may follow: `Name--1.0--r2--x86_64.tar.bz2`.
   - Architecture: `x86_64`, or `noarch` for a package that holds only scripts and data.
   - EXT: `bz2` (the usual one), `gz`, `xz` or `zst`. At most 4 GB.
2. **Layout:** every file sits inside `Name/` and there is exactly one version folder `Name/Version/`.
   No absolute paths, no `..`.
3. **No special files:** no setuid or setgid files and no device files. (A program cannot gain root
   rights by being installed.)
4. **Architecture** in the file name and in `Resources/Architecture` matches the computer (`x86_64`)
   or is `noarch`.
5. **Dependencies:** each line of `Resources/Dependencies` is `ProgramName`, or `ProgramName >= version`
   (also `>`, `=`, `==`); empty lines and `#` comments are skipped. `ProgramName` is the folder name in
   `/Programs` (case matters: `GTK+`, `FFmpeg`, `Lua`). Each one must be installed, in that version or a
   newer one. Leaving the file out only gives a warning, but list what you need: it tells users why a
   package does not fit.
6. **Compiled files** (programs and libraries):
   - 64-bit x86 only.
   - Every library they need (`NEEDED` in `readelf -d`) is on the system or inside the package.
   - They may not need a newer C library than the system's: **glibc 2.38** today (from 0.9.7 on). A
     program built on a newer distribution usually needs `GLIBC_2.39` or later and is refused.
7. Last, a warning (not a failure) if the package has neither a menu entry in `share/applications/`
   nor a command in `bin/`: there would be nothing to start.

The same version of a program cannot be installed twice: installing a file whose `Name/Version` is
already in `/Programs` is refused.

## How to build one

The simplest way is to build **on GoboRefined itself**, so the program is compiled against the same
libraries and glibc it will run with.

1. Install the build tools you need (gcc, make, autotools, meson... most are already on the system).
2. Configure the program to install into its own Gobo folder:

       ./configure --prefix=/Programs/MyApp/1.0 --sysconfdir=/Programs/MyApp/1.0/Resources/Defaults/Settings
       make -j$(nproc)
       sudo make install

   (meson: `meson setup build --prefix=/Programs/MyApp/1.0`; CMake: `-DCMAKE_INSTALL_PREFIX=/Programs/MyApp/1.0`.)
3. Add the menu entry, `share/applications/myapp.desktop`, if the program does not install one. Use an
   icon name from the system icon theme (Papirus), e.g. `Icon=utilities-system-monitor`, or ship your own
   icon under `share/icons/hicolor/...`.
4. Write the three `Resources` files:

       echo x86_64 > /Programs/MyApp/1.0/Resources/Architecture
       printf '%s\n' 'GTK+ >= 3.20' > /Programs/MyApp/1.0/Resources/Dependencies
       printf '%s\n' '[Name] MyApp' '[Version] 1.0' '[Summary] One line about what it does' \
          '[License] GPL-3.0-or-later' '[Homepage] https://example.org/myapp' > /Programs/MyApp/1.0/Resources/Description

   `[Summary]` is shown on the Apps page before installing. A longer `[Description]` line is allowed too.
5. Pack it, owned by root, with the path starting at the program name:

       tar -cjf MyApp--1.0--x86_64.tar.bz2 --owner=0 --group=0 -C /Programs MyApp/1.0
       sha256sum MyApp--1.0--x86_64.tar.bz2 > MyApp--1.0--x86_64.tar.bz2.sha256

6. Check it: `gobo-app-check MyApp--1.0--x86_64.tar.bz2` must end with `RESULT compatible`.
   Then try it on the Apps page: install, start it from the menu, remove it.

A program that is only scripts (Lua, Python, shell) does not need compiling: put the files in the folder
layout above, use `noarch` if you like, and pack it the same way.

A ready-made Linux build of a program (a `.tar.gz` from its website) can be packed the same way, if it
passes rule 6. Programs built for current distributions often need a newer glibc than 2.38; for those an
AppImage that targets an older glibc, or building from source, is the way.

## Examples in this repository

- [`apps/lxtask/build.sh`](../apps/lxtask/build.sh): a C program (autotools), menu entry renamed, one
  dependency.
- [`apps/qalculate-gtk/build.sh`](../apps/qalculate-gtk/build.sh): a larger C++ program that carries
  its own library (libqalculate) inside the package and finds it through `-Wl,-rpath,/Programs/Name/Version/lib`.
- [`apps/photos/make-package.sh`](../apps/photos/make-package.sh): scripts only, no compiling; a plain
  `sh` script that makes the package from the files next to it.
- [`apps/lib.sh`](../apps/lib.sh): the helper those build scripts use (pinned source check, the
  `Resources` files, packing). It expects to run as root in a GoboLinux build root, as in our lab; on an
  installed GoboRefined, steps 2-6 above do the same by hand.

## What a package can rely on

The system's own programs are in `/Programs`; `ls /Programs` lists them and their versions, and those are
the names to use in `Dependencies`. As of 0.10.4 they include glibc 2.38, GTK 3, Mesa 26.3 (OpenGL 4.6,
Vulkan 1.4 loader), libva 2.24, FFmpeg, Lua and Python. The desktop is Awesome with GoboRefined's own
taskbar and menu; a program with a normal `.desktop` file appears in the menu and the search after
installing.

Updates of GoboRefined can change these versions. When a release raises or removes something
packages commonly use, the release notes say so.

## Sharing a package

Publish the `.tar.bz2` file with its `.sha256` next to it, and say which GoboRefined version you tested
it on. Users install it from a folder, a USB stick or an FTP server on the Apps page; the page warns them
to install programs only from people they trust, because an installed program can do everything the user
can do.
