# How to install software on GoboRefined (this spin of GoboLinux 017.01)

GoboLinux has no `apt`, `dnf` or app store. Every program lives in its own folder,
`/Programs/<Name>/<Version>`, and is linked into the system with `SymlinkProgram`.

## What works

**Build a program from its GoboLinux recipe** (needs internet; compiles from source, so it can take
minutes to hours; needs your password because it writes to `/Programs`):

    sudo Compile Htop

- The first `Compile` downloads the whole recipe collection (about 500 MB, into
  `/Data/Compile/Recipes`). After that, `FindPackage --types=recipe <name>` shows whether a recipe exists.
- Recipe names are the folder names at <https://github.com/gobolinux/Recipes> (case matters:
  `Gimp`, `Htop`, `VLC`...).
- Checked in the build VM: `Compile --batch Figlet` as root fetched the recipe collection, built
  Figlet 2.2.4 and linked it; it ran. Without `sudo` you get *"Needs write access to /Programs"*.
- To remove a program again: `sudo RemoveProgram <Name>`.

**Package files from Settings > Software > Apps** (`Name--Version--x86_64.tar.bz2`, GoboLinux's own
package format): pick the file, the page checks that it fits this system, then installs it. Apps added this
way stay through system updates and are removed on the same page. How to make such a file:
[making-apps.md](making-apps.md).

**AppImages**: make the file executable and double-click it. It runs if it needs glibc 2.38 or older.

**Programs that ship as ready-made Linux builds** (like ONLYOFFICE on this spin) can be unpacked
into `/Programs/<Name>/<Version>` by hand and linked with `sudo SymlinkProgram <Name>`.

## What does not work (and why)

- **`InstallPackage <Name>`** installs *binary* packages. The GoboLinux 017 package server lists
  only two packages (Fuse, UnionFS-Fuse; checked 2026-11), so it almost always fails. It also needs
  root. The "command not found" hint used to suggest it; on this spin the hint now says
  `sudo Compile <Name>` instead.
- **Old or broken recipes.** Many recipes are years old; the source download may be gone or the code
  may not build with gcc 14. There is no guarantee a given `Compile` succeeds.
- **The hint's program list is older than the recipe collection.** For `apt` it suggested `Sun-JDK`
  (`apt` is also the name of an old Java tool), but the current recipe collection has no `Sun-JDK`
  and no `OpenJDK` recipe at all, so `sudo Compile Sun-JDK` stops with "no recipe". Java would have
  to be unpacked by hand from an upstream binary build (as ONLYOFFICE is).
- **Flatpak, Snap and app stores**: not on the image.
