#!/bin/sh
# GoboRefined A/B: mount hook. The work is done by /sbin/goboab-root (one place for the logic).

[ "$root" = gobo ] || return 0
[ -e /goboab/done ] && return 0

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

_gmode=normal
[ "$(getarg gobo.system-changes=)" = off ] && _gmode=safe

if goboab-root "$NEWROOT" "$(getarg gobo.slot=)" \
        "$(label_uuid_to_dev "$(getarg gobo.root=)")" \
        "$(label_uuid_to_dev "$(getarg gobo.data=)")" "$_gmode"; then
    : > /goboab/done
else
    # rd.emergency=reboot is passed by GRUB on the first tries of a new slot, so a slot that
    # cannot be assembled reboots and GRUB falls back to the previous one.
    die "GoboRefined: could not assemble the root file system (see messages above)"
fi
unset _gmode
