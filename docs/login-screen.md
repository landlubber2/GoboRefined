# Login screen (LXDM 0.5.3) — stage 3

Status (2026-11-13): **works in the build VM.** LXDM starts from `inittab` at boot, shows the gobo11 greeter
on tty7, logs the lab user into the normal Awesome desktop, and returns to the greeter after "Log out".
Since spin 0.4 `gobo-install` enables it by default (steps below); `--text-login` keeps the console login.
Installs of ISO 0.4 tested in the VM: see "Verified on installs of ISO 0.4" at the end.
Screenshot: `docs/screenshots/0.4-login-greeter.png`.

## What is in the package

`/Programs/LXDM/0.5.3` (built by hand, `spin/build-programs.sh lxdm`; GTK 3 greeter, PAM, no ConsoleKit,
no systemd). The spin's own files come from `spin/lxdm/` and end up in `/Programs/LXDM/Settings`, which
`SymlinkProgram` links into `/System/Settings` (= `/etc`):

| File (as LXDM sees it) | Source | Purpose |
|---|---|---|
| `/etc/lxdm/lxdm.conf` | `spin/lxdm/lxdm.conf` | theme `Gobo11`, login name typed (no user list), no session/language pickers, X restarted after each logout (`reset=1`) |
| `/etc/lxdm/Xsession` | `spin/lxdm/Xsession` | loads `/System/Environment/Cache`, then runs the user's `~/.xinitrc` through the login shell under `dbus-launch` |
| `/etc/lxdm/PostLogout` | `spin/lxdm/PostLogout` | kills the user's leftover `xss-lock` (it spins at 100% CPU once its X server is gone) |
| `/etc/pam.d/lxdm` | `spin/lxdm/pam.d-lxdm` | modelled on `/etc/pam.d/login` (system-auth/-account/-session/-password) |
| `share/lxdm/themes/Gobo11/` | `spin/lxdm/Gobo11/` + Industrial's layout | our wallpaper (rendered from the Awesome theme at 1920x1080), Inter, dark entry field, title image `login.png` ("GoboRefined" + "an unofficial spin of GoboLinux 017.01", drawn by `spin/lxdm/render-title.sh`) |

Two problems found and fixed on the way (both are in the files above):
- LXDM's stock `Xsession` sources `/etc/xprofile` with bash; on GoboLinux that file is zsh syntax, so the
  GoboLinux environment (Lua paths) was never loaded and awesome died at once (`module 'lgi' not found`).
  The session then ended immediately and the greeter came back.
- `make install` writes straight into `/etc/lxdm` and `/etc/pam.d/lxdm`; the build script moves those into
  `/Programs/LXDM/Settings` before `SymlinkProgram`.

## Enabling it on an installed system (what gobo-install would do)

1. The ISO already contains `/Programs/LXDM` (spin 0.4); the installer copies it with the rest of `/Programs`.
   `/etc/lxdm` and `/etc/pam.d/lxdm` are symlinks made by `SymlinkProgram` and are copied too.
2. **inittab** — append to `$DEST/Programs/BootScripts/Settings/inittab` (the file `/etc/inittab` points to):

   ```
   # Graphical login screen (LXDM) on tty7
   x:2345:respawn:/System/Index/sbin/lxdm-binary
   ```

   Use `lxdm-binary` (foreground), not the `lxdm` wrapper script or `-d`, so init respawns it if it dies.
   LXDM picks display `:0` on `vt7`; the text consoles tty1–6 stay as they are. No BootScripts change is
   needed (the stock `Graphic` script that calls `kdm` stays unused).
3. **`.zlogin`** — do not append the `startx`-on-tty1 block when LXDM is enabled. (If it is left in, a
   console login on tty1 tries a second X server on `:0`, which fails within seconds; the block's own
   20-second rule then keeps the user in the shell — harmless, just pointless.)
4. **`--autologin`** — instead of `agetty --autologin` on tty1, set it in
   `$DEST/Programs/LXDM/Settings/lxdm/lxdm.conf`:

   ```
   [base]
   autologin=<login name>
   ```

   (Not tested.)
5. **Keyboard layout in the greeter** (not tested): the greeter runs before `~/.xinitrc`'s `setxkbmap`, so it
   uses X's default layout (US). For a non-US layout write
   `$DEST/System/Settings/X11/xorg.conf.d/00-keyboard.conf`:

   ```
   Section "InputClass"
      Identifier "keyboard"
      MatchIsKeyboard "on"
      Option "XkbLayout" "<layout>"
   EndSection
   ```

6. Session command: nothing to configure. `Xsession` always runs `~/.xinitrc` (written by `apply.sh`), so the
   greeter and `startx` give the same desktop; `lxdm.conf`'s `session=awesome` is only the fallback for users
   without `~/.xinitrc`.

## Verified (build VM, keyboard only)

- Boot with the inittab line -> greeter on tty7 (`0.4-login-greeter.png`).
- Type login name, Enter, password, Enter -> full gobo11 desktop (taskbar, PulseAudio, xss-lock, picom,
  `LANG`/`XDG_*`/`GTK_PATH` set); PCManFM starts from it.
- Log out (`awesome.quit()`) -> X restarts, greeter returns, no leftover `xss-lock`.

## Not tested

- The greeter's Quit button (reboot / shut down menu) — needs a mouse click outside Awesome.
- `autologin=`, the keyboard-layout file, a wrong password (only PAM's normal path was exercised).
- Lock screen (Win+L / idle) inside a greeter session (xss-lock starts as before; locking itself not tried).
- Real hardware, multi-monitor greeter, HiDPI.
- The build VM was put back to text login afterwards (inittab restored) so the lab tools keep working.

## Verified on installs of ISO 0.4 (2026-11-13, VM)

- UEFI install with defaults and layout `pl`: greeter at boot; the greeter's X server uses `pl`
  (`00-keyboard.conf` works; AltGr+A types "ą"); a wrong password returns to "User:" and the next login works;
  Lock/unlock, Log out (greeter back, nothing of the session left once PulseAudio's 20 s idle exit has passed),
  Restart and Shut down from the power menu by simulated mouse clicks.
- `--autologin` (BIOS): desktop at boot without a password. Log out shows the greeter, which then asks for the
  password (LXDM only autologins at its first start, i.e. once per boot).
- `--text-login` (BIOS): no LXDM; tty1 login + `startx` as in 0.2; Log out returns to the tty1 prompt.

Still not tested: the greeter's Quit button, multi-monitor greeter, HiDPI, real hardware.
