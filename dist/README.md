# GoboRefined — test ISO

GoboRefined is an **unofficial** spin of GoboLinux 017.01 (not made by the GoboLinux developers).

`GoboRefined-0.6.iso` (2,863,726,592 bytes, about 2.9 GB) — check it against `GoboRefined-0.6.iso.sha256` before use:
sha256 `0f01edeb327f476213a2ac9b26a5bfde78e3b2e2af639fce148461216e19bdf1`.
It needs a **USB stick of 4 GB or larger**. (`GoboRefined-0.5.iso` is kept next to it.)

## New in 0.6 (fixes and wishes from the 0.5 test on the real PC)

- **Keyboard no longer gets stuck** after menus and pop-ups: a click anywhere outside a menu closes it and the
  window you clicked gets the keyboard. If anything still holds the keyboard, **Win+Escape** closes every pop-up
  and frees it.
- **Wi-Fi adapter (TP-Link Archer TX20U Plus)** is switched out of its "driver CD" mode by itself, with retries
  and a log file (`/var/log/gobo-wifi-switch.log`). Not tried with the adapter yet — see below.
- **Network icon** shows the real state: wired, Wi-Fi with signal bars, connecting, or disconnected.
- **Virtual desktops**: one desktop to start with; **Win+Shift+Tab** lists them (add, remove, switch); the
  number of desktops is kept after logging out. **Changed:** previous/next desktop is now **Win+,** and **Win+.**
  (Win+Escape used to be "previous desktop").
- **Screenshots**: **Win+Shift+S** asks Area / Window / Whole screen; Print takes the whole screen. Pictures go to
  `Pictures/Screenshots` and onto the clipboard.
- **Clipboard history**: **Win+Shift+V** lists the last 20 copied texts and pictures; Enter pastes one.
- **Default folders**: Desktop, Documents, Downloads, Music, Pictures (with Screenshots), Videos.
- **File manager**: **Ctrl+F** (or the magnifier button) searches by part of a name, in the folder only or in
  all folders inside it; a **"USB drives"** entry lists plugged-in sticks.
- **Desktop icons**: files in your Desktop folder appear on the desktop, plus a **Trash** icon. Deleted files go
  to the Trash, where they can be restored; items older than 6 months (or 1 / 3) are removed automatically.
- **Folder colours**: right click a folder in your home folder → "Folder colour...".
- USB notification has a single "Safely remove" button; clicking the notification opens the stick.

## Please test on the real PC — in this order

1. **Wi-Fi with the TP-Link Archer TX20U Plus** (live session or installed):
   1. Plug the adapter in and wait about 15 seconds. It should switch by itself (no command needed any more).
   2. Click the network icon on the taskbar (left of the battery). A list of Wi-Fi networks should appear.
      Click yours and type the Wi-Fi password in the window that pops up. The icon should show signal bars.
   3. If it fails, send these three: the file **`/var/log/gobo-wifi-switch.log`**, and the output of
      **`lsusb`** and **`dmesg | tail -40`** (typed in a terminal).
2. Keyboard after menus: open the dots menu, click into a terminal, type — it should arrive in the terminal.
   If the keyboard ever seems dead, press **Win+Escape** and say what you did just before.
3. New shortcuts: **Win+Escape**, **Win+Shift+Tab** (desktops), **Win+Shift+S** (screenshot),
   **Win+Shift+V** (clipboard history), **Ctrl+F** in the file manager. Changed: **Win+,** / **Win+.** =
   previous / next desktop.
4. Desktop icons and Trash: save a file to the Desktop folder, delete it, restore it from the Trash icon.
5. Screenshots and the clipboard history on NVIDIA (only tried on the VM's graphics).
6. Anything from the 0.5 list that still bothers you (title-bar double click, terminal paste, USB sticks,
   ONLYOFFICE, the `apt` hint).

## Write it to a USB stick

1. Check the checksum (on Windows: `certutil -hashfile GoboRefined-0.6.iso SHA256`, compare with the `.sha256` file).
2. Write the ISO with a tool that writes the image as-is ("DD image mode" in Rufus, or balenaEtcher).
   Everything on the stick is erased.
3. Boot the PC from the stick. Pick a language and a keyboard map.
4. At the prompt type `startx` to look around without installing, or `gobo-install` to install.

**`gobo-install` erases the whole disk you choose.** No dual boot. Use a spare PC or a spare drive.

## Logging in after the install

- Remove the stick and reboot. The boot menu shows "GoboRefined 0.6 (GoboLinux 017.01)". The **login screen**
  appears: type your login name, Enter, your password, Enter. The keyboard layout chosen during the install also
  applies on the login screen.
- **Log out** (power menu) returns to the login screen. **Restart** and **Shut down** work from the power menu.
- `gobo-install --autologin` logs you in without a password at boot. After "Log out" the login screen
  appears and asks for the password as usual.
- **Text login instead**: `gobo-install --text-login`. You log in on the text console and the desktop starts by
  itself; "Log out" returns to the text login prompt.
- Other options: `gobo-install --help` (for example `--swap 1024` for a 1 GB swap file).
- A second user (`sudo AddUser -f "Full Name" login`, then set a password) gets the look, the folders and the
  Trash icon, but its desktop keyboard layout is US until `setxkbmap` in that user's `~/.xinitrc` is changed.

## Only tested in a VirtualBox VM

Works there in both BIOS and UEFI mode (see `HANDOFF.md` for the exact checks). Not yet tried: the Wi-Fi adapter,
exFAT/NTFS sticks, ONLYOFFICE / screenshots / desktop icons on NVIDIA, NVMe drives, a physical second monitor,
HiDPI screens. If a second monitor does not come on, open the launcher menu (dots icon) -> Desktop -> Detect
Displays. Plain text files have no default program yet (only Vim is on the image; double-clicking a .txt file
shows an empty "Choose Application" list).
