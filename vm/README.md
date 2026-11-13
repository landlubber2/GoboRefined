# Stage 2 — VM checklist

Status: **VM created** (2026-11-11). Live boot not fully verified yet — start VirtualBox and confirm the ISO boots.

## Checklist

- [x] Download GoboLinux **017.01** ISO
- [ ] Verify checksum if published with the release
- [x] Create a VM on this Windows host (**VirtualBox 7.2.22**)
- [ ] Attach the ISO and boot the Live environment (VM started once; confirm boot in GUI)
- [ ] If installing inside a VM: use an **MBR** partition table (upstream: GPT/UEFI bootloader install in VMs has been flaky)
- [ ] Take a snapshot before experiments
- [x] Note host path to the ISO / VM name here for the next session:

```
ISO path: C:\dev\Revamp and Modernize gobolinux\GoboLinux-017.01-x86_64.iso
VM name / hypervisor: GoboLinux-017.01 / Oracle VirtualBox 7.2.22
VM files: C:\dev\Revamp and Modernize gobolinux\vm\GoboLinux-017.01\
Disk: 40 GB VDI (empty; for optional install)
RAM / CPUs: 4096 MB / 2
Firmware: BIOS (not EFI) — matches MBR-friendly install path
Network: NAT
Notes: VirtualBox was installed via winget (Oracle.VirtualBox). Guest additions / clipboard not required for first boot.
```

## Host → VM clipboard bridge

VirtualBox clipboard sharing often fails on GoboLinux Live. Use the local bridge instead:

```powershell
cd "C:\dev\Revamp and Modernize gobolinux\vm\clipboard-bridge"
.\Start-ClipboardBridge.ps1
```

In the VM browser open: **http://10.0.2.2:8765/**  
Click **Copy all**, then in the guest terminal paste with **Ctrl+Shift+V** (not Ctrl+V).

- Edit `vm/clipboard-bridge/payload.txt` on the host (recovery commands are already there), then Reload in the guest.
- Optional: `.\Start-ClipboardBridge.ps1 -WatchHostClipboard` syncs the Windows clipboard into `payload.txt`.

## Useful commands

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm "GoboLinux-017.01" --type gui
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm "GoboLinux-017.01" poweroff
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" snapshot "GoboLinux-017.01" take "clean-before-experiments"
```

## After Stage 2

Return to `docs/goals.md` and fill look / functionality checkboxes from real observation — still without assuming a single “proper” modernization path.
