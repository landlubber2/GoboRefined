# GoboLinux context (facts only)

Snapshot for later exploration. Not a modernization plan.

## Current release

- **Version:** 017.01 (announced around 2025-03-31 / 2025-04-01)
- Live environment ISO; can run from USB/DVD or install to disk
- Stewardship transition noted in the 017.01 announcement (founder stepping down; project continuing under new stewardship)

## Distinctive idea

GoboLinux rethinks the traditional Unix filesystem layout. Programs live in versioned, self-contained directories (commonly under `/Programs`), with a managed index/symlink layer (commonly under `/System`) and optional compatibility for conventional paths (e.g. GoboHide-related approaches). Exact tree details should be verified from upstream docs and a running system.

## Key upstream repositories

| Repo | Role |
| --- | --- |
| [gobolinux/Documentation](https://github.com/gobolinux/Documentation) | Project documentation |
| [gobolinux/Scripts](https://github.com/gobolinux/Scripts) | Core utility scripts |
| [gobolinux/Compile](https://github.com/gobolinux/Compile) | Build tool |
| [gobolinux/Recipes](https://github.com/gobolinux/Recipes) | Package recipes (large; optional clone) |
| [gobolinux/LiveCD](https://github.com/gobolinux/LiveCD) | Live CD / installer-related scripts |
| [gobolinux/GoboNet](https://github.com/gobolinux/GoboNet) | Minimal network manager |

Org: https://github.com/gobolinux

## Official links

- Site: https://gobolinux.org
- Wiki / knowledge base: https://wiki.gobolinux.org
- 017.01 release notes (site): https://gobolinux.org/release_notes_017.01.html
- LiveCD release tag: https://github.com/gobolinux/LiveCD/releases/tag/017.01

## Known VM note (from 017.01 docs)

In a VM, installing the bootloader onto a GPT/UEFI setup has been reported to fail. Prefer an **MBR** partition table for VM installs. Bare metal GPT was reported to work in their testing; bootloader can also be configured manually if needed.

## Maintenance posture

The wiki has described limited maintenance / few active developers, with encouragement for people willing to work on the project themselves. Confirm current status on the wiki before assuming support bandwidth.
