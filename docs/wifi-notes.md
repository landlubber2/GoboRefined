# Wi-Fi on 017.01: GoboNet (stage 3 notes)

Nothing was built for Wi-Fi. This is what the image already has, read from the build VM (2026-11-13).
The VM has no wireless device, so nothing here was tried against a real access point.

## What it is

- **GoboNet 0.12** (`/Programs/GoboNet`): `gobonet` (bash front end) + `gobonet_backend` (small C helper that
  calls `setuid(0)` and then runs `/bin/rfkill`, `/bin/ifconfig`, `/bin/iwlist`, `/bin/wpa_supplicant`,
  `/bin/dhcpcd`, `/bin/killall`). Wi-Fi + DHCP only: no static IP, no VPN, no 802.1X/enterprise UI.
- Commands: `gobonet list`, `gobonet connect "<essid>"`, `gobonet connect_no_password "<essid>"`,
  `gobonet connect_wired`, `gobonet disconnect`, `gobonet forget "<essid>"`, `gobonet autoconnect`.
- Known networks are stored per user as `wpa_supplicant` snippets in `~/.cache/GoboNet/wifi/` (mode 0700;
  `wpa_passphrase` output, so the PSK hash, not the plain password).
- Password prompt: `pinentry` if present (on the image it is `pinentry-qt`, a Qt dialog), else `zenity`,
  else the terminal.
- `~/.zlogin` runs `gobonet autoconnect` in the background at every console login (not over ssh).
- **Awesome widget** `gobo.awesome.gobonet` (LuaRocks): shows a wired or Wi-Fi signal icon; left/right click
  opens a menu with the scanned networks (strongest first, signal icons), "Disconnect"/"Forget" for the
  current network, "Rescan", and "Wired network (eth0)". It also re-runs autoconnect after a long gap
  between updates (resume from sleep).

## How a user connects

Click the network icon on the taskbar (right side, left of the battery) -> pick a network -> type the
password in the pinentry dialog. Next time it reconnects by itself at login. From a terminal:
`gobonet list`, then `gobonet connect "Name"`.

## Does our taskbar still have it?

Yes. `look/gobo11/awesome/rc.lua` still adds `gobonet.new()` to the status area, and the gobo11 theme
provides its icons (`wifi_0..3`, `wifi_up/down`, `wired_up/down`). Verified in the VM: the icon shows
"wired up" and a click opens the menu (`docs/screenshots/0.4-network-menu.png`, wired entry + Rescan,
since the VM has no Wi-Fi card).

## Problem found, fixed in the ISO script

`gobonet_backend` is **not setuid** on the 017.01 image (`-rwxr-xr-x root`), although GoboNet's own
`make install` does `chmod 4755` on it. As a normal user the backend cannot become root, so every privileged
step fails: in the VM `gobonet_backend interface-up lo` returns 1 as `lab` and 0 as root. So Wi-Fi from the
taskbar cannot have worked for a normal user on the stock image. `spin/build-iso.sh` (0.4) now restores the
bit (`chmod 4755 .../GoboNet/Current/bin/gobonet_backend`), the same way `gobolight` is shipped.

## Not checked (needs Wi-Fi hardware)

- Scanning, connecting (WPA2-PSK, open), autoconnect at login and after resume, forget.
- Whether the installed system keeps the setuid bit (the installer copies `/Programs` with ProfileInstall;
  Xorg's setuid bit evidently survives, so it probably does).
- Firmware for common cards (iwlwifi, rtw88, brcm...) on the image; `rfkill` soft-block handling.
- WPA3 / enterprise networks, hidden SSIDs, captive portals — GoboNet has no UI for these.

## 0.5: TP-Link Archer TX20U Plus (Realtek RTL8852AU / RTL8832AU)

The user's `lsusb` on the real PC showed `0bda:1a2b Realtek Semiconductor Corp. DISK`: the adapter
starts as a virtual "driver CD" and must be switched into Wi-Fi mode. The 6.12.16 kernel's `rtw89`
driver has no USB support (that arrived in later kernels), so an out-of-tree driver is needed.

What the 0.5 image adds (built in the build VM with `spin/build-programs.sh`):

| Piece | Where | What it does |
|---|---|---|
| `usb_modeswitch` 2.6.1 (binary only) | `/Programs/USB-ModeSwitch/2.6.1` | sends the "eject" that switches the adapter |
| udev rule `40-gobo-realtek-wifi.rules` | same program, `lib/udev/rules.d` (linked into `/System/Index/lib/udev/rules.d`) | on plug-in **and at boot** (the boot script's `udevadm trigger --action=add` coldplug) runs `usb_modeswitch -K -v 0bda -p 1a2b`; marks the fake disk "no policy" so the USB automounter (devmon) leaves it alone |
| driver `8852au.ko` (lwfinger/rtl8852au, commit 865ab0f, 2024-05-06) | `/Programs/RTL8852AU/20240506/lib/modules/6.12.16-Gobo/updates/`, linked from `/Programs/Linux/Current/lib/modules/6.12.16-Gobo/updates/8852au.ko` | the Wi-Fi driver; `depmod` lists it, so udev loads it by itself |

After the switch the adapter should re-appear as `2357:013f` (TP-Link "AX1800", also `2357:0141`)
or a Realtek `0bda:8832`-family ID. `modinfo 8852au` lists aliases for `2357:013f`, `2357:0140`,
`2357:0141`, `0bda:8832`, `0bda:885a`, `0bda:885c` and others. If the switched adapter shows an ID
that is *not* in that list (e.g. `0bda:b832`/`0bda:b852`, an RTL8852**B**U chip), this driver is the
wrong one; send the `lsusb` line.

Checked in the build VM (no such adapter there): the module builds against the image's own kernel
tree, `modprobe 8852au` loads it without errors (the kernel only notes that an unsigned out-of-tree
module "taints" it, which is normal), `modinfo` shows the aliases above. The udev rule's two parts
were checked with a copy that matched the VM's virtual USB stick: the RUN command ran on plug-in and
devmon skipped the device because of the "no policy" mark. The actual mode switch and the driver
talking to the hardware can only be tested on the real PC.

Interface name: the image does not rename network interfaces (the wired one is still `eth0`), and
the driver names its interface `wlan0` (`ifname` module parameter). GoboNet does not depend on the
name anyway: it picks the interface whose `/sys/class/net/*/uevent` says `DEVTYPE=wlan` or that has a
`phy80211` link. GoboNet scans with `iwlist` (wireless extensions); the kernel has
`CONFIG_CFG80211_WEXT=y`, so that should work with this driver too.

### Test on the real PC (0.5 ISO, live session or installed)

1. Plug the adapter in and wait about 10 seconds.
2. Click the network icon on the taskbar (left of the battery). A list of Wi-Fi networks should
   appear. Click yours and type the Wi-Fi password in the window that pops up.
3. If the list stays empty or only shows "Wired network": open a terminal and type
   `sudo usb_modeswitch -KW -v 0bda -p 1a2b` (your password), wait 10 seconds, then try step 2 again.
   (Alternative manual switch: `sudo eject /dev/sr0` — or `sr1` if the PC has a DVD drive.)

If it still does not work, send the output of these three commands:

    lsusb
    dmesg | tail -40
    ip link

## 0.6: the switch did not happen by itself on the real PC

Report on 0.5: plugging the adapter in did nothing; typing `sudo usb_modeswitch -KW -v 0bda -p 1a2b`
later switched it and Wi-Fi then worked (so the driver and GoboNet are fine; the automatic path failed).

What was checked in the build VM and on the 0.5 live image (squashfs of `dist/GoboRefined-0.5.iso`):
- udevd (Eudev) reads rules from `/usr/lib/udev/rules.d` (= `/System/Index/lib/udev/rules.d`),
  `/System/Settings/udev/rules.d` and `/run/udev/rules.d` (strings in the binary). The 0.5 image has
  `40-gobo-realtek-wifi.rules` linked in `/System/Index/lib/udev/rules.d`, the binary path
  `/System/Index/bin/usb_modeswitch` exists, the match keys are right, and the boot task
  (`Eudev/Resources/Tasks/Udev`) does `udevadm trigger --action=add`, so the rule is read and fires.
- So the most likely cause is timing: 0.5 ran `usb_modeswitch` synchronously inside udev's handling of
  the device's "add" event, while the kernel was still setting the device up (usb-storage probing the
  virtual CD). The same command typed seconds later worked. Without the adapter this cannot be proven.

What 0.6 does instead (robust rather than a guess at one cause):
- **`gobo-wifi-switch`** (`/Programs/USB-ModeSwitch/2.6.1/bin`, source `spin/gobo-wifi-switch`): leaves
  udev at once (`setsid`), waits 4 s, then up to 4 tries of `usb_modeswitch -K -W -v 0bda -p 1a2b -b BUS
  -g DEV` 3 s apart, then 2 tries of `eject /dev/srN` (the virtual CD drive), stopping as soon as the
  `0bda:1a2b` device is gone; afterwards it loads `8852au` if udev has not. One copy runs at a time
  (`flock`); a second copy waits and finds nothing to do. Every step is logged with time stamps.
- **Three triggers**: the udev rule on the USB device ("add", also the coldplug at boot), a second udev
  rule on its CD drive (`sr*`, after usb-storage has set it up), and the desktop: Awesome looks for
  `0bda:1a2b` every 3 s (also right after login) and runs `sudo -n gobo-wifi-switch --session`
  (`look/gobo11/awesome/spin/wifi_switch.lua`; NOPASSWD rule for exactly that command, written into
  the image's sudoers by `spin/build-iso.sh`). The desktop shows "Wi-Fi adapter found / ready" or
  "could not switch it on" notifications.
- Emulated in the build VM with a copy of the wrapper and rule matched to the virtual USB stick
  (`80ee:0030`): plug-in -> udev -> detached wrapper -> retries, and "switched" logged once the stick was
  pulled during the retries; the same at boot with the stick already plugged in (coldplug, log written
  6 s after boot); the session path through sudo (and `sudo -n` refuses the wrapper with any other
  argument, and any other command). The real eject and the adapter re-appearing need the real PC.

### If it still does not switch by itself (0.6)

Plug the adapter in, wait 30 seconds, then send the log file:

    cat /var/log/gobo-wifi-switch.log

(also `lsusb`, and `dmesg | tail -40`). The log shows which trigger ran (udev / session), each attempt
and what usb_modeswitch answered. Switching by hand still works: `sudo gobo-wifi-switch` (prints the
same lines) or `sudo usb_modeswitch -KW -v 0bda -p 1a2b`.
