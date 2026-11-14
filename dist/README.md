# GoboRefined — test ISO

GoboRefined is an **unofficial** spin of GoboLinux 017.01 (not made by the GoboLinux developers).

`GoboRefined-0.5.iso` (2,860,646,400 bytes, about 2.9 GB) — check it against `GoboRefined-0.5.iso.sha256` before use.
It needs a **USB stick of 4 GB or larger**.

## New in 0.5 (fixes for what the 0.4 test on the real PC found)

- **New name** on the login screen, the boot menu, the welcome text and in the installer: GoboRefined.
- **Double click on a window's title bar** maximizes it, a second double click restores it.
- **Terminal copy and paste**: selecting text with the mouse copies it; **right click pastes**;
  Ctrl+Shift+C / Ctrl+Shift+V also work. Text copied in other programs pastes into the terminal and back.
- **USB sticks**: plugging one in shows a notification ("Open" shows it in the file manager); a drive
  icon on the taskbar has "Safely remove". No more broken `Media` link in `/Mount/Media`.
- **Wi-Fi for the TP-Link Archer TX20U Plus**: the adapter is switched out of its "driver CD" mode
  automatically, and its driver (RTL8852AU) is on the ISO. Not tried with the adapter yet — see below.
- **ONLYOFFICE** (Desktop Editors 10.0) for .docx/.xlsx/.pptx and OpenDocument files; double-clicking such a
  file in the file manager opens it. This is why the ISO grew to about 2.9 GB.
- **"command not found" hint** (for example after typing `apt`) now says `sudo Compile <Program>` and points to
  `/Programs/GoboSpin/Current/share/doc/software-install.txt`, which explains how to install software here.
- The search window (right click on the dots button, or Win+R) keeps working after it was closed by a click
  outside it or with its power button (before, it then opened without accepting typing until the next login).
- The installer's summary names the login method, and its last line matches it.

## Please test on the real PC — in this order

1. **Wi-Fi with the TP-Link Archer TX20U Plus** (live session or installed):
   1. Plug the adapter in and wait about 10 seconds.
   2. Click the network icon on the taskbar (left of the battery). A list of Wi-Fi networks should appear.
      Click yours and type the Wi-Fi password in the window that pops up.
   3. If the list stays empty or only shows "Wired network": open a terminal and type
      `sudo usb_modeswitch -KW -v 0bda -p 1a2b` (your password), wait 10 seconds, then try step 2 again.
      (Alternative manual switch: `sudo eject /dev/sr0` — or `sr1` if the PC has a DVD drive.)
   4. If it still does not work, send the output of `lsusb`, `dmesg | tail -40` and `ip link`.
2. Double click on a title bar (maximize / restore); dragging windows still works.
3. Terminal: select text, right click to paste; paste from Firefox into the terminal and back.
4. A USB stick: notification, "Open", copying a file onto it, "Safely remove" from the taskbar drive icon.
5. ONLYOFFICE: create and save a document; open a .docx by double-clicking it. (On NVIDIA it was not tried.)
6. Type `apt` in a terminal and read the hint.

## Try it on a PC

1. Write the ISO to a USB stick (4 GB or larger) with a tool that writes the image as-is
   ("DD image mode" in Rufus, or balenaEtcher). Everything on the stick is erased.
2. Boot the PC from the stick. Pick a language and a keyboard map.
3. At the prompt type `startx` to look around without installing, or `gobo-install` to install.

**`gobo-install` erases the whole disk you choose.** No dual boot. Use a spare PC or a spare drive.

## Logging in after the install

- Remove the stick and reboot. The boot menu shows "GoboRefined 0.5 (GoboLinux 017.01)". The **login screen**
  appears: type your login name, Enter, your password, Enter. The keyboard layout chosen during the install also
  applies on the login screen.
- **Log out** (power menu) returns to the login screen. **Restart** and **Shut down** work from the power menu.
- `gobo-install --autologin` logs you in without a password at boot. After "Log out" the login screen
  appears and asks for the password as usual (no automatic login again until the next boot).
- **Text login instead**: install with `gobo-install --text-login`. You then log in on the text console and the
  desktop starts by itself; "Log out" returns to the text login prompt.
- Other options: `gobo-install --help` (for example `--swap 1024` for a 1 GB swap file).

## Only tested in a VirtualBox VM

Works there in both BIOS and UEFI mode (see `HANDOFF.md` for the exact checks). Not yet tried: Wi-Fi hardware,
exFAT/NTFS sticks, ONLYOFFICE on NVIDIA, NVMe drives, a physical second monitor, HiDPI screens. If a second
monitor does not come on, open the launcher menu (dots icon) -> Desktop -> Detect Displays.
