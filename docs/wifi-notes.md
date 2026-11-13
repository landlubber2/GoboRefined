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
