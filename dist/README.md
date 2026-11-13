# GoboLinux 017.01 modernized spin — test ISO

`GoboLinux-017.01-spin.iso` — check it against `GoboLinux-017.01-spin.iso.sha256` before use.

## Try it on a PC

1. Write the ISO to a USB stick (4 GB or larger) with a tool that writes the image as-is
   ("DD image mode" in Rufus, or balenaEtcher). Everything on the stick is erased.
2. Boot the PC from the stick. Pick a language and a keyboard map.
3. At the prompt type `startx` to look around without installing, or `gobo-install` to install.

**`gobo-install` erases the whole disk you choose.** No dual boot. Use a spare PC or a spare drive.

After installing, remove the stick, reboot, log in with the user you created; the desktop starts by itself.

## Only tested in a VirtualBox VM

Works there in both BIOS and UEFI mode. Not yet tried: real hardware, USB boot, Wi-Fi, NVMe drives,
a physical second monitor. If a second monitor does not come on, open the launcher menu (dots icon) ->
Awesome WM -> Detect Displays.
