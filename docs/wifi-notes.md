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
