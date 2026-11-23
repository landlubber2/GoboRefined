#!/usr/bin/env bash
# Register the lab VM "GoboLinux-017.01" from this checkout, wherever it is (any folder, any drive letter).
#
# VirtualBox stores full paths for the disks outside the machine folder (vm/GoboLinux-017.01/*.vdi) and for
# the ISO images. This script rewrites those paths to the folder this checkout is in, keeps a copy of the
# old settings file (.vbox.before-register), then registers the VM.
#
# Use on a new computer, or after the drive letter changed:
#   1. If VirtualBox still lists the VM from the old place:  VBoxManage unregistervm GoboLinux-017.01
#      (NEVER add --delete: that deletes the disks.)
#   2. bash vm/register-vm.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && (pwd -W 2>/dev/null || pwd))"
vbox="$root/vm/GoboLinux-017.01/GoboLinux-017.01/GoboLinux-017.01.vbox"
VB=VBoxManage
command -v VBoxManage >/dev/null 2>&1 || VB="/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
[ -f "$vbox" ] || { echo "no VM settings file at $vbox" >&2; exit 1; }
if "$VB" list vms | grep -q '"GoboLinux-017.01"'; then
   echo "VirtualBox already has GoboLinux-017.01:" >&2
   "$VB" showvminfo GoboLinux-017.01 --machinereadable | grep '^CfgFile=' >&2
   echo "Unregister it first (without --delete) if it is the old place." >&2
   exit 1
fi
cp -- "$vbox" "$vbox.before-register"
sed -i -E \
   -e "s#location=\"[^\"]*/(vm/GoboLinux-017\.01/[^/\"]+\.vdi)\"#location=\"$root/\1\"#g" \
   -e "s#location=\"[^\"]*/(GoboLinux-017\.01-x86_64\.iso)\"#location=\"$root/\1\"#g" \
   -e "s#location=\"[^\"]*/(dist/[^/\"]+\.iso)\"#location=\"$root/\1\"#g" \
   "$vbox"
"$VB" registervm "$vbox"
echo "registered from $root"
"$VB" list hdds | grep -E '^(Location|State):' | paste - - | grep -v 'State: *created' || echo "all disks found"
