#!/bin/sh
# GoboRefined A/B: root=gobo gobo.layout=btrfs gobo.slot=a|b gobo.root=UUID=<pool> gobo.data=UUID=<pool>
#                  [gobo.system-changes=off]
# Written by GRUB's menu (grub.cfg on GOBO_BOOT, made by gobo-install).

[ -z "$root" ] && root=$(getarg root=)
[ "$root" = gobo ] || return 0

type wait_for_dev > /dev/null 2>&1 || . /lib/dracut-dev-lib.sh

_gslot=$(getarg gobo.root=)
_gdata=$(getarg gobo.data=)
if [ -z "$_gslot" ] || [ -z "$_gdata" ]; then
    die "GoboRefined: root=gobo needs gobo.root= and gobo.data= on the kernel command line"
fi
rootok=1
wait_for_dev -n "$(label_uuid_to_dev "$_gslot")"
wait_for_dev -n "$(label_uuid_to_dev "$_gdata")"
unset _gslot _gdata
