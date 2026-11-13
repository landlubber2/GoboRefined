# GoboLinux 017.01 modernized spin — test ISO

`GoboLinux-017.01-spin-0.4.iso` (2.47 GB) — check it against `GoboLinux-017.01-spin-0.4.iso.sha256` before use.
(`GoboLinux-017.01-spin-0.2.iso` is the previous test ISO.)

New in 0.4:
- **Graphical login screen** (LXDM) instead of logging in on a text console.
- **Files** (PCManFM): taskbar button next to Terminal, or Win+E.
- **Sound control** (PaVuControl): left click the volume icon (right click mutes, wheel changes the volume).
- **Display settings** (LxRandr): launcher menu (dots icon) -> Desktop -> Displays...
- Fonts Inter and JetBrains Mono, Papirus icons (dark/light follow the power menu's switch).
- Wi-Fi from the taskbar network icon should now work for normal users (its helper is setuid again; not
  tried with real Wi-Fi yet).

From 0.2: app menu on the dots button (left click) with search on right click or Win+R; power menu
(search window's power button or Ctrl+Alt+Del) with lock, log out, restart, shut down and a dark/light switch;
Win+L locks.

## Try it on a PC

1. Write the ISO to a USB stick (4 GB or larger) with a tool that writes the image as-is
   ("DD image mode" in Rufus, or balenaEtcher). Everything on the stick is erased.
2. Boot the PC from the stick. Pick a language and a keyboard map.
3. At the prompt type `startx` to look around without installing, or `gobo-install` to install.

**`gobo-install` erases the whole disk you choose.** No dual boot. Use a spare PC or a spare drive.

## Logging in after the install

- Remove the stick and reboot. The **login screen** appears: type your login name, Enter, your password, Enter.
  The keyboard layout chosen during the install also applies on the login screen.
- **Log out** (power menu) returns to the login screen. **Restart** and **Shut down** work from the power menu.
- `gobo-install --autologin` logs you in without a password at boot. After "Log out" the login screen
  appears and asks for the password as usual (no automatic login again until the next boot).
- **Text login instead** (the 0.2 behaviour): install with `gobo-install --text-login`. You then log in on the
  text console and the desktop starts by itself; "Log out" returns to the text login prompt.
- Other options: `gobo-install --help` (for example `--swap 1024` for a 1 GB swap file).

## Only tested in a VirtualBox VM

Works there in both BIOS and UEFI mode. Not yet tried: real hardware, USB boot, Wi-Fi, NVMe drives,
a physical second monitor, HiDPI screens. If a second monitor does not come on, open the launcher menu
(dots icon) -> Desktop -> Detect Displays.
