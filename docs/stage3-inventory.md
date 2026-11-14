# Stage 3 inventory (build VM, 2026-11-13)

Facts gathered over ssh from the build VM (snapshot `iso-build-env-2`, an installed 017.01 with the build tools).
The live image has the same `/Programs` set. Nothing here was compiled yet.

## Build tools

| Tool | Version / state |
|---|---|
| gcc | 14.2.0 |
| make | 4.3 |
| cmake | 3.16.4 |
| meson, ninja | **broken**: `/System/Aliens/PIP/3.8/bin/meson` exists but the Python modules are missing (`No module named 'mesonbuild'` / `'ninja'`). A `Ninja` recipe (1.8.2, 1.10.2) exists. |
| pkg-config | 0.29.2 |
| python3 | 3.8.1 (no `python`/`python2`); site-packages: pip, setuptools, Mako, **PyQt5 5.14.1**, libxml2. **No PyGObject (`gi`), no pycairo.** |
| autoconf / automake / libtool | 2.69 / 1.16.4 / 2.4.6 |
| perl | 5.30.1 |
| git | 2.25.0 |
| Compile | 017-GIT, runs. Local recipe tree `/Data/Compile/Recipes` is **empty**; `GetRecipe` is present; the recipe store `github.com/gobolinux/Recipes` clones fine (3783 programs; a copy is in `/Data/Build/Recipes-git` from snapshot `iso-build-env-3`). A full `Compile` run was not tried. |

## Recipes in the upstream recipe store (latest version listed)

| Need | Recipe | Not in store |
|---|---|---|
| File manager | PCManFM 1.2.5 (+ LibFM 1.2.5, Menu-Cache 1.0.2); Thunar 1.8.15; XFE 1.43.2; Caja 1.9.90 | SpaceFM, Nemo, PCManFM-Qt |
| Thunar deps | EXO 0.12.11, LibXFCE4UI 4.14.1, LibXFCE4Util 4.14.0, Tumbler 0.2.9 | Xfconf |
| Sound control | PaVuControl 4.0 (also 2.0, 3.0); XFCE4-Mixer | Pavucontrol-Qt, PNMixer, Volumeicon |
| Display tool | LxRandr 0.3.1, GRandR 0.1 | ARandR |
| Login screen | LXDM 0.5.3, XDM 1.1.12 | LightDM, LightDM-GTK-Greeter, SLiM, Ly |
| Session/auth | ConsoleKit 0.4.6, ConsoleKit2 1.0.2, Polkit 0.112 | elogind |
| Network | NetworkManager 1.8.0, Network-Manager-Applet 1.4.0, ConnMan 1.29 | IWD |
| Python GTK | PyGObject 3.42.0, PyCairo 1.21.0 | |
| Other | LXAppearance 0.6.2, LXSession 0.5.3, LXPanel | |

Recipe dates matter: most of these were written for 2016–2020 library versions, close to what 017.01 ships.

## Libraries (pkg-config)

| Library | Version |
|---|---|
| GTK 3 | 3.24.13 |
| GTK 2 | **not installed** (no `gtk+-2.0`, no `libgtk-x11-2.0`) |
| GLib | 2.63.5 |
| gtkmm-3.0 / sigc++-2.0 | 3.24.2 / 2.10.2 |
| Qt | 5.14.1 (Qt5Core) |
| libpulse | 13.0 (PulseAudio 13.0 running per session from `.xinitrc`) |
| ALSA | 1.2.2 |
| libcanberra (+ gtk3) | 0.30 |
| json-glib | 1.4.4 |
| PAM | Linux-PAM **1.3.1 installed**: `libpam.so.0.84.2`, headers in `include/security`, `/System/Settings/pam.d/*` present; no `pam.pc` (1.3.x does not ship one) |
| elogind / ConsoleKit / polkit | **none installed** (`xss-lock` logs "org.freedesktop.login1 was not provided") |
| D-Bus | 1.12.16 |
| udev | Eudev 3.2.9 (libudev 243) |
| Xorg server | 1.20.7; libX11 1.6.9; libXrandr 1.5.1 |
| Pango / FreeType / Fontconfig | 1.44.7 / 23.1.17 (libtool version) / 2.13.92 |
| GObject-Introspection | present; typelibs for Gtk-3.0, Gdk-3.0, Pango, Notify, Secret, Soup, xrandr-1.3 ... |
| vte, libnm, libfm, menu-cache, libxklavier | not installed |

## Already on the image for stage 3 needs

| Need | Present |
|---|---|
| File manager | **none** graphical (only GTK's file chooser inside apps) |
| Sound | NCPAMixer 1.3.3 (terminal mixer for PulseAudio), PulseAudio-Ctl 1.67 (CLI), ALSA-Utils; no GUI mixer |
| Display | XRandR-Tool 1.5.2 (`xrandr`, added by the spin in 0.1); no GUI |
| Network | GoboNet 0.12 (`gobonet`, `gobonet_backend`, used by the Awesome widget), WPA_Supplicant 2.9, Wireless-Tools 29, DHCPCD, IPRoute2, LibNL 3.5.0, RFKill; Bluez 5.54; no NetworkManager/ConnMan/iwd |
| Display manager | **none** (stock `Graphic` script calls a missing `kdm`; spin uses tty1 `startx`); XSecureLock + XSS-Lock for locking |
| Other GUI apps | Firefox 136.0_bin, GParted 1.1.0, Audacious 4.0.3, RawTherapee, MuPDF 1.16.1, Zenity 3.32.0 (GTK3), Srain, gvim, htop |
| Terminal | RXVT-Unicode 9.22 (default, with Tabbedex), XTerm 353 |

## Fonts, icons, GTK theme (before stage 2)

| Item | State |
|---|---|
| Fonts | DejaVu 2.37 (default sans/mono/serif via fontconfig), Lode Fonts 3.0 (Lode Sans/Mono, stock urxvt font), Xorg legacy fonts (Luxi, Bitstream Charter/Courier, Lucida, Utopia, Syriac, ...); 974 entries in `fc-list` |
| Icon themes | Adwaita 3.20 (~2,700 files, full-colour app icons mostly missing for third-party apps), hicolor 0.17 (61 files); one loose `firefox.png` |
| GTK theme | Adwaita (built into GTK 3), dark via `gtk-application-prefer-dark-theme`; only other themes: `Default`, `Emacs` (key themes) |
| Cursor | Adwaita (XCursor-Themes 1.0.6 also present) |

Stage 2 added Inter 4.1, JetBrains Mono 2.304 and Papirus 20260801 (see `HANDOFF.md`).

## Added in 0.6 (file-manager half, 2026-11-14)

| Program | Version | What |
|---|---|---|
| GoboFiles | 0.6 | the spin's own: `gobo-trash` (Trash window, GTK 3, C), `gobo-trash-purge` (deleting from the Trash, 1/3/6-month age limit), `gobo-folder-colour` + the PCManFM menu entry "Folder colour..." (libfm custom action in `share/file-manager/actions`). Sources `spin/gobofiles/`. 96 KB installed. |
| LibFM | 1.2.5 (rebuilt) | `spin/patches/libfm-1.2.5-gobo.patch`; custom actions enabled again (generated C files ship in the tarball, no Vala needed) |
| PCManFM | 1.2.5 (rebuilt) | `spin/patches/pcmanfm-1.2.5-gobo.patch` |

Used from the image, nothing downloaded: Zenity 3.32.0 (colour chooser, `--extra-button`), FindUtils, XProp, GLib's own
freedesktop trash support (`g_file_trash` works without gvfs for files on the home file system).
