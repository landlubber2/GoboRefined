# Draft upstream bug reports (GoboLinux 017.01)

Drafts only — nothing here has been posted. Each was observed on the 017.01 x86_64 ISO in VirtualBox 7.2.22.
Before posting: re-check against upstream's issue tracker for duplicates, and post under the user's own account.

| File | Short version | Likely repository |
| --- | --- | --- |
| `1-chpasswd-noop.md` | `chpasswd` exits 0 and changes nothing | gobolinux/Recipes (Shadow) |
| `2-grub-install-efi.md` | `grub-install` for UEFI builds a loader that cannot read the disk | gobolinux/Installer |
| `3-xrandr-missing.md` | The `XRandR` package has no `xrandr` command | gobolinux/Recipes or LiveCD |
| `4-graphic-boot-kdm.md` | The `Graphic` boot script starts `kdm`, which is not shipped | gobolinux/BootScripts |

A fifth problem, the Installer hanging in `GenGrubConf`/`grub-mkconfig`, is written up in
`../installation-bug-report.md`.
