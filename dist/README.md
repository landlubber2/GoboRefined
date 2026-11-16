# GoboRefined 0.8.4 — laptop sound firmware, Bluetooth pairing, newer firmware for all hardware

GoboRefined is an **unofficial** spin of GoboLinux 017.01 (not made by the GoboLinux developers).

| File | Size | sha256 |
|---|---|---|
| `GoboRefined-0.8.4.update` | 2,683,650,048 bytes (2.7 GB) | `4aebc0d8f6b6c5264bf8ab487fe4b1d835baa9f8b23f0fbeb15172f15b791be5` |
| `GoboRefined-0.8.4.iso` | 2,816,737,280 bytes (2.8 GB) | `97ccc5d89f8add6a7ab20a4c956bb235c34ad65f6827f9c820fbba0569c7a1dc` |

## How to update (from 0.8.3, 0.8.2 or 0.8.1)

Copy `GoboRefined-0.8.4.update` onto the PC, then **Settings > Updates > Install update from file...** (or in a
terminal `sudo gobo-update /path/to/GoboRefined-0.8.4.update`) and restart. Going back:
`sudo gobo-update --rollback`. Files, accounts, light/dark and the wallpaper stay.

## What is new

- **Laptop sound (Intel):** the Sound Open Firmware for current Intel laptops (sof-bin 2026.09.2) replaces the
  2020 version that had no Tiger Lake files ("SOF firmware and/or topology file not found", only "Dummy Output").
- **Newer firmware for all hardware:** the linux-firmware collection of 2026-10-19 (Wi-Fi, Bluetooth, graphics,
  sound, ...) replaces the one of 2025-03-09. Nothing the old set had is lost; firmware for phone/ARM chips and
  server network cards is left out. The image did not grow.
- **Graphics:** Intel and AMD graphics use the X server's modesetting driver (as current distributions do).
  NVIDIA is unchanged.
- **Touchpads:** tap to click (one finger = click, two = right click) and two-finger scrolling.
- **Bluetooth pairing works from anywhere:** when a phone, keyboard or speaker wants to pair, a "Bluetooth pairing"
  window appears (check that both screens show the same number and press Pair, or type a PIN). Paired devices are
  trusted, so they reconnect by themselves. The computer shows up on other devices under its own name (not
  "BlueZ 5.54"). The taskbar Bluetooth menu is new: on/off, connect/disconnect paired devices, "Bluetooth
  settings...". In Settings, devices without a name are tucked away under "Other devices without a name".
  Bluetooth **sound** (speakers, headphones) still does not work: they pair, but play nothing.
- **Accounts:** removing a person and adding the same login again works now.
- **USB sticks:** helper partitions (Ventoy's VTOYEFI, EFI partitions) no longer pop up as drives; the stick's
  main partition still opens.

## Please check on the laptop

1. **Sound output:** play something (e.g. a YouTube video). Settings > Sound should list the built-in speakers,
   not "Dummy Output".
2. **Headphone jack:** plug headphones in: sound should move to them, and back to the speakers when unplugged.
3. **Microphone:** in Settings > Sound (Input devices), speak: the level bar should move.
4. **Pair the phone:** Settings > Bluetooth > Search for devices, put the phone into pairing mode, press Pair:
   both show a number, press Pair on both. Also try starting the pairing from the phone.
5. **Pair the speaker:** it should pair without questions (sound over Bluetooth is not expected yet).
6. **Touchpad:** tap to click, two-finger scroll.
7. **The phone's Bluetooth list** shows the computer under its name.

If sound still fails, run these in a terminal and send the output (or use Settings > About > Save system report):

```
sudo dmesg | grep -i sof
aplay -l
pactl list cards short
```

If the speaker works but the headphone jack or microphone does not, that is a known limit of the sound
configuration data on this base (alsa-lib 1.2.2): please report which part fails.

# GoboRefined 0.8.3 — hotfix for Intel laptop graphics

GoboRefined is an **unofficial** spin of GoboLinux 017.01 (not made by the GoboLinux developers).

| File | Size | sha256 |
|---|---|---|
| `GoboRefined-0.8.3.update` | 2,734,542,848 bytes (2.7 GB) | `75b18965db301a37b632d9f81ecb7d325754934380dd17883dc37204498554ab` |
| `GoboRefined-0.8.3.iso` | 2,867,658,752 bytes (2.9 GB) | `b621802d745234f1bdd3029b7bbe12ac4cc3c70cebf042ba57a498100428f244` |

- **Fix:** on laptops with Intel graphics (seen on a ThinkPad with Tiger Lake Xe graphics) the desktop showed
  only a thin strip at the top: the X server picked the old "intel" driver. Intel graphics now use the kernel's
  modesetting driver (`/System/Settings/X11/xorg.conf.d/20-intel-modesetting.conf`). Other graphics (NVIDIA,
  AMD, virtual machines) are not affected. Nothing else changed from 0.8.2.
- This is the first release **built from the repository alone** (`build/build.sh`, see `BUILDING.md`): the stock
  017.01 ISO, the checkout and pinned downloads, compiled from scratch in a fresh VM.
- **Update from 0.8.2 (or 0.8.1):** copy `GoboRefined-0.8.3.update` onto the PC, then
  `sudo gobo-update /path/to/GoboRefined-0.8.3.update` (or Settings > Updates > Install update from file...) and
  restart. Going back: `sudo gobo-update --rollback`. On an Intel laptop where the desktop is unusable, do it from a
  text console (Ctrl+Alt+F2, log in, run the command, then `sudo reboot`).

# GoboRefined 0.8.2 — Settings app, Bluetooth and hotspot (experimental), desktop fixes

GoboRefined is an **unofficial** spin of GoboLinux 017.01 (not made by the GoboLinux developers).

| File | Size | sha256 |
|---|---|---|
| `GoboRefined-0.8.2.update` | 2,734,637,056 bytes (2.7 GB) | `228c5d7fab6746dfb8b92676207d3926a4a4c1d1ceaef7278d162f56b43c5500` |
| `GoboRefined-0.8.2.iso` | 2,867,724,288 bytes (2.9 GB) | `9e3e55afa0547738a9d92f9b97a82cb5fd6150ded460d595169a6fad8b356e87` |

Check them against the `.sha256` files before use (Windows: `certutil -hashfile GoboRefined-0.8.2.update SHA256`).
The 0.8.1, 0.8 and 0.6 files are kept next to them.

## Already running 0.8.1? Update with the file (no reinstall)

1. Copy `GoboRefined-0.8.2.update` onto the PC (or a USB stick; "Safely remove" before unplugging).
2. In a terminal: `sudo gobo-update /path/to/GoboRefined-0.8.2.update` and answer "yes" to restart (about one
   minute). After this update you can also do it from **Settings > Updates > Install update from file...**.
3. After the restart the desktop says "System updated". Files, accounts, light/dark and your wallpaper stay.
   Going back: `sudo gobo-update --rollback` (or Settings > Updates > Go back to the previous version).

## What is new in 0.8.2

- **Settings** (power menu, dots menu, app search): Appearance (light/dark, **your own wallpaper**), Accounts
  (password, add/remove people, administrator or standard, automatic login), Updates, Remote access (SSH, off by
  default; root can never log in over it), Network, **Bluetooth**, **Hotspot**, Sound, Displays, Trash, About
  ("Save system report"). Starting Settings again brings the open window to the front.
- **Bluetooth (experimental):** on/off, "Search for devices", pair / connect / disconnect / forget, pairing
  questions as dialogs. Says "No Bluetooth adapter found" when there is none. Bluetooth **sound** (headphones,
  speakers) does not work yet: the sound system has no Bluetooth part.
- **Wi-Fi hotspot (experimental):** shares the cable connection over the Wi-Fi adapter: name, password (8–63
  characters), on/off. Turning it on disconnects this PC from its Wi-Fi network (it says so first); turning it
  off reconnects. Off again after a restart. Says "Needs a Wi-Fi adapter" when there is none.
- **Desktop:** thin "show desktop" strip at the right end of the taskbar; power menu by keyboard (arrows,
  Enter, Escape; "Lock" is selected when it opens); clicks no longer swallowed by a leftover menu sheet after
  plugging the Wi-Fi adapter in (Win+Escape also clears it); system partitions hidden from the USB-drive pop-ups;
  Wi-Fi regulatory database added; new users no longer see an old "System updated" notice.

## Please confirm on the real PC

1. **Clicks after plugging the Wi-Fi adapter in/out**: plug, wait, unplug, plug again — clicks must keep working
   (if not: Win+Escape, then Settings > About > Save system report).
2. **FAT-fs message gone**: after a start, `dmesg | grep -i fat` should show no "Volume was not properly
   unmounted" for the system's boot partition.
3. **Bluetooth**: Settings > Bluetooth: switch on, Search, pair a mouse/keyboard or phone, connect, disconnect,
   forget; untick "Switch Bluetooth on at every start", restart, check it stays off. (Never tested with real
   Bluetooth hardware.)
4. **Hotspot**: with the cable plugged in, Settings > Hotspot: set name + password, switch on, join from a phone,
   open a web page on the phone; switch off and check the PC rejoins its Wi-Fi. The TX20U Plus driver may not
   support hotspot mode — then the page says so and nothing changes. (Tested only with virtual Wi-Fi radios.)
5. **Remote access from another computer**: Settings > Remote access on, then from the other computer
   `ssh yourlogin@<address shown>`; switch off again.

---

# GoboRefined 0.8.1 — first update (bug fixes)

GoboRefined is an **unofficial** spin of GoboLinux 017.01 (not made by the GoboLinux developers).

| File | Size | sha256 |
|---|---|---|
| `GoboRefined-0.8.1.update` | 2,734,350,336 bytes (2.7 GB) | `f55a83076892183ffb289105e294647e9e1b5c63c5a4f9136fce2afee9ce75f1` |
| `GoboRefined-0.8.1.iso` | 2,867,462,144 bytes (2.9 GB) | `05049abb143ee64ff3bdf7f418c4c6b3d6c5d2ba782563b199071e23f70335ea` |

Check them against the `.sha256` files before use (Windows: `certutil -hashfile GoboRefined-0.8.1.update SHA256`).
The 0.8 and 0.6 files are kept next to them.

## Already running 0.8? Update with the file (no reinstall)

1. Copy `GoboRefined-0.8.1.update` onto the PC (or a USB stick; "Safely remove" before unplugging).
2. In a terminal: `sudo gobo-update /path/to/GoboRefined-0.8.1.update` and answer "yes" to restart
   (about one minute for checking and writing).
3. After the restart the desktop says "System updated". Your files, accounts, light/dark choice and
   settings stay. `sudo gobo-update --status` shows 0.8.1 running. Going back: `sudo gobo-update --rollback`.

A new install from the 0.8.1 ISO works as described for 0.8 below (whole disk erased, at least 32 GB).

## What is fixed in 0.8.1 (from your 0.6 test list)

- **Wi-Fi menu** — the network menu now notices a Wi-Fi adapter plugged in after the desktop started, switches it
  on and scans; "Rescan" scans the adapter that is there now. Without an adapter it says "No Wi-Fi adapter found".
- **"Wired network" without a cable** — shown as "Wired network (eth0): no cable" and does nothing.
- **USB mouse (or keyboard) dead after re-plugging** — the screen's input system never heard about devices
  plugged in later (a GoboLinux quirk with `/dev`); fixed for the graphical login (not for "text login").
- **Power button** — a short press opens the power menu on the desktop (press again to close it); at the login
  screen or a text console it shuts the PC down cleanly.
- **Win key** — tapping Win alone opens the dots menu; holding Win for shortcuts works as before.
- **Screenshots** — Print and Win+Shift+S work while a menu is open (the menu closes first).
- **Text files** — open in **L3afpad**, a small text editor (also in the app search).
- **Second user** — users added after the install get the keyboard layout chosen at install time.
  (A user you already added under 0.8 keeps "us": change the `setxkbmap` line in their `~/.xinitrc`.)
- **Passwords file** — `/System/Settings/shadow` is no longer readable by every user.
- Small things: "Pcmanfm" gone from the desktops list; the light/dark switch stays on your desktop; searching
  "Displays" finds the display settings.

Not fixed: the freeze when pulling out the Wi-Fi adapter (could not be reproduced), desktop icons not redrawing
after moving, the taskbar icons of minimized windows (please describe what looks wrong).

## Please confirm on the real PC

1. **Wi-Fi menu after plugging the adapter in, with no network cable connected first**: start the PC without
   cable and without the adapter, log in, plug the adapter in, wait ~10 s, click the network icon: networks
   should be listed; connect to yours; then "Rescan". Also: unplug and plug the adapter in again, then connect.
2. **Mouse re-plug**: unplug the USB mouse, wait 5 s, plug it in: the pointer must move without a restart.
3. **Power button**: short press on the desktop -> power menu; at the login screen -> the PC switches off.
4. **Win tap**: tap Win -> dots menu; Win+E, Win+Up and other shortcuts still work and do not open it.
5. Network icon shows "no cable" in the menu when the cable is out.

---

# GoboRefined 0.8 (still valid for installing; 0.8.1 adds the fixes above)

GoboRefined is an **unofficial** spin of GoboLinux 017.01 (not made by the GoboLinux developers).

| File | Size | sha256 |
|---|---|---|
| `GoboRefined-0.8.iso` | 2,867,200,000 bytes (2.9 GB) | `d31f8c979a1dd0889f31f1e5bee028a1827306f90eb003ac34e93a5a23e8ba38` |
| `GoboRefined-0.8.update` | 2,734,075,904 bytes (2.7 GB) | `7b02b424b6a8f77759104ff87a5b1004bad4fd2f0ab93bbb03daf072ff41249b` |

Check them against the `.sha256` files before use (Windows: `certutil -hashfile GoboRefined-0.8.iso SHA256`).
The ISO needs a **USB stick of 4 GB or larger**. `GoboRefined-0.6.iso` is kept next to it as a fallback.

## Before you start: a reinstall is needed

- **Coming from 0.6 (or older), you must reinstall.** 0.8 lays out the disk in a new way; there is no upgrade
  from 0.6. Copy your files somewhere else first.
- **The whole disk you choose is erased.** No dual boot, no keeping other partitions.
- **The disk must have at least 32 GB.** On disks of 48 GB or more each system slot gets 16 GB (room for more
  programs later); on smaller disks 12 GB.

## What "A/B" means for you

The disk now holds **two copies of the system** ("slot A" and "slot B") plus a **data part** with your home
folder, your accounts, your settings and programs you add yourself.

- A **system update** is one file (`GoboRefined-<version>.update`). It is written into the copy you are *not*
  using, while you keep working. At the next restart the computer starts the new copy.
- If the new copy does not start (twice), the computer **goes back to the old copy by itself** and the desktop
  says "System update undone". You can also go back by hand.
- Your files, accounts, passwords and settings are on the data part and are **kept** by updates and by going back.
- The boot menu shows both copies. Each has an entry **"without my system changes"**: it starts the system as it
  was installed, ignoring changes made to system files afterwards (programs you compiled, edited settings).
  Use it if a change of yours stops the system from starting. Your home folder is still there.

## Install (through the menus)

1. Write the ISO to a USB stick with a tool that writes the image as-is ("DD image mode" in Rufus, or
   balenaEtcher). Everything on the stick is erased.
2. Boot the PC from the stick (UEFI is fine). Pick a language and a keyboard map.
3. At the prompt type **`gobo-install`**. Menus ask, one after the other: the disk (a list with model and size;
   disks under 32 GB are marked too small; the USB stick you started from is marked and cannot be chosen) → a red
   warning that names the disk which will be **erased** → your full name, login name, password (twice) → whether
   the administrator (root) uses the same password (otherwise its own, twice) → computer name → time zone
   (region, then city) → keyboard layout (common ones first, "more layouts" at the end) → options (automatic
   login, text login, swap file size) → a summary. Nothing is written before you choose **Install** there.
   A progress bar follows (about 2 minutes), then "Restart now".
4. Remove the stick when the PC restarts. Log in on the login screen.

Esc or Cancel at any question offers to quit without changing anything. `gobo-install --plain` asks the old way
(line by line); `gobo-install --help` lists all options.

## Update with a file

    sudo gobo-update /path/to/GoboRefined-<version>.update

It checks the file (signature and checksum), writes it into the other slot, and asks whether to restart.
The file must belong to you (or root) and must not be writable by others; a file on a USB stick usually is fine.
Copy the file completely before using it (on a stick: "Safely remove" or `sync` before unplugging).

    sudo gobo-update --status      # both slots, their versions, which one starts next
    sudo gobo-update --rollback    # start the other slot from the next restart on
    sudo gobo-update --reset-system-changes
                                   # at the next restart, forget changes made to system files since the
                                   # install (accounts, passwords and home folders stay)

## Please test on the real PC — in this order

1. **Install on real UEFI** through the menus. Note whether the disk list looks right (model and size) and
   whether the USB stick is marked "you started from it". **NVMe disks** appear as `/dev/nvme0n1`: say if one
   is in the PC and whether it is listed and installs.
2. **Boot menu**: after the install it shows "GoboRefined 0.8 (slot A)", its "without my system changes" and
   "safe graphics" entries, and "Slot B: empty". If the PC starts straight into another system or shows no menu,
   say so (the boot entry is named "GoboLinux" in the firmware's boot list).
3. **An update as a dry run**: copy `GoboRefined-0.8.update` onto a USB stick, plug it in, and in a terminal
   run `sudo gobo-update /Mount/Media/<stick>/GoboRefined-0.8.update`. It puts the same 0.8 into **slot B**
   (takes about a minute). Restart: the menu should now show 0.8 twice and start slot B. `sudo gobo-update --status`
   should say slot B is running.
4. **Rollback**: `sudo gobo-update --rollback`, restart: slot A starts again. Run `--rollback` once more to go
   back to B if you like.
5. The 0.6 basics on the real PC: login/logout, desktop icons and Trash, search, screenshots, clipboard history,
   USB stick, light/dark mode, Wi-Fi adapter.
6. If something fails, send: `sudo gobo-update --status`, the file `/var/log/gobo-update.log`, and
   `dmesg | grep GoboRefined` (the start of the system writes its checks there).

## Still open — NOT fixed in 0.8

These are the problems from the 0.6 test (list "0.6.2" in `docs/roadmap.md`); they are meant for the first real
update, not for 0.8:

1. Wi-Fi menu lists networks only while some network is already connected; Rescan does not help.
2. Trouble connecting to Wi-Fi after the adapter was unplugged and plugged in again.
3. PC froze when the Wi-Fi adapter was unplugged (not reproduced).
4. A USB mouse stops working after being unplugged and plugged in again, until restart.
5. Short press of the power button does nothing.
6. Tapping the Win key alone opens the dots menu.
7. "Wired network (eth0)" is listed with no cable connected.
8. Screenshots do not work while a menu is open.
9. Desktop icons do not redraw after being moved until an empty spot is clicked.
10. Taskbar icons of minimized windows sometimes look wrong.
11. Plain text files have no default program.
12. A second user gets the US keyboard layout on the desktop.
13. Small things: "Pcmanfm" in the desktops list; light/dark switch jumps to desktop 1; app search misses "Displays".

## Good to know

- GRUB itself (the boot loader program) is never updated by `gobo-update`; only its menu can be, and the
  previous menu is kept. If a menu ever shows entries like "$ver_a" and starts nothing: press `c` and type
  `configfile $prefix/grub.cfg.old`, Enter.
- After a power cut the start of the system checks the data part first; that is normal and quick.
- Only tested in a VirtualBox VM (BIOS and UEFI). Not tried yet: real UEFI firmware, NVMe drives, the Wi-Fi
  adapter with 0.8, HiDPI screens, a physical second monitor.
