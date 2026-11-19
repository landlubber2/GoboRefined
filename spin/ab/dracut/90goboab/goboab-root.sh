#!/bin/sh
# GoboRefined A/B (0.8): assemble the root file system in the initramfs.
#
#   goboab-root NEWROOT SLOT SLOTDEV DATADEV normal|safe [LAYOUT]
#
# LAYOUT (gobo.layout= on the kernel command line): empty or "ext4" = the 0.8 layout (slots GOBO_A,
# GOBO_B and GOBO_DATA are partitions); "btrfs" = the 0.10 layout (prototype, docs/ab-btrfs-plan.md):
# SLOTDEV and DATADEV are both the GOBO_POOL partition; the slot is subvolume @system-SLOT (read-only),
# the data subvolume @data (holds the same folders as GOBO_DATA).
#
# Layers of "/" (overlayfs), top to bottom:
#   upper    GOBO_DATA:/System-Overlay/upper   every change made to system files after the install
#            (a throw-away tmpfs instead in "safe" mode = "without my system changes")
#   install  GOBO_DATA:/System-Overlay/install the machine's own settings written by gobo-install
#            (accounts, hostname, fstab, keyboard, login screen); read-only here
#   slot     GOBO_A or GOBO_B                  the pristine system image; read-only
# Mounted on top: GOBO_DATA:/Users -> /Users, GOBO_DATA:/Variable -> /Data/Variable;
# the data partition itself -> /System/Data, the slot -> /System/Slot (both for gobo-update).
#
# Also done here, before anything uses the overlay:
#   - "gobo-update --reset-system-changes" (flag file): upper -> previous-upper, new empty upper
#     that keeps only the account files;
#   - first boot of a different system version: generated caches listed in the slot's
#     share/gobo-update/generated-caches are removed from the overlay layers (the booted system
#     regenerates them: gobo-update --boot-task).
# All paths removed here are fixed names below $G or validated list entries; nothing is derived
# from unchecked input.

NEWROOT="$1"
SLOT="$2"
SLOTDEV="$3"
DATADEV="$4"
MODE="$5"
LAYOUT="${6:-ext4}"

G=/goboab
O=$G/data/System-Overlay
ACCOUNTS="System/Settings/passwd System/Settings/shadow System/Settings/group System/Settings/gshadow"
SPIN_VERSION_FILE=Programs/GoboSpin/Current/share/spin-version
CACHE_LIST=Programs/GoboSpin/Current/share/gobo-update/generated-caches

say()  { echo "GoboRefined: $*" > /dev/kmsg 2>/dev/null; echo "GoboRefined: $*"; }
fail() { say "$*"; exit 1; }

case "$SLOT" in a|b) ;; *) fail "gobo.slot must be a or b (got '$SLOT')" ;; esac
case "$MODE" in normal|safe) ;; *) fail "unknown mode '$MODE'" ;; esac
case "$LAYOUT" in ext4|btrfs) ;; *) fail "unknown layout '$LAYOUT'" ;; esac
[ -b "$SLOTDEV" ] || fail "slot device $SLOTDEV not found"
[ -b "$DATADEV" ] || fail "data device $DATADEV not found"
[ -n "$NEWROOT" ] && [ -d "$NEWROOT" ] || fail "no NEWROOT"

modprobe -q overlay 2>/dev/null
modprobe -q ext4 2>/dev/null
mkdir -p $G/slot $G/data $G/mem

if [ "$LAYOUT" = btrfs ]
then
   # 0.10 (prototype): one btrfs pool. Copy-on-write, so no check before mounting (a power cut
   # leaves the last committed state). @data read-write first (the compression option applies to
   # the whole file system), then the slot's subvolume read-only (it also has the btrfs ro flag).
   modprobe -q btrfs 2>/dev/null
   mount -t btrfs -o rw,noatime,compress=zstd:3,subvol=@data "$DATADEV" $G/data || fail "cannot mount subvolume @data of $DATADEV"
   mount -t btrfs -o ro,noatime,subvol=@system-$SLOT "$SLOTDEV" $G/slot || fail "cannot mount slot $SLOT (subvolume @system-$SLOT of $SLOTDEV)"
   # The swap file lives in its own subvolume (no copy-on-write, no compression: btrfs needs that
   # for swap files); mounted at /Data/Variable/swap below. The boot scripts only "mount -a -f".
   SWAPVOL=""
   mkdir -p $G/swap
   if mount -t btrfs -o rw,noatime,subvol=@swap "$DATADEV" $G/swap 2>/dev/null
   then SWAPVOL=1
   else say "no subvolume @swap (no swap file)"
   fi
else
# Data partition: e2fsck in preen mode before mounting. After a power cut it replays the journal
# itself ("recovering journal"; the kernel would do the same at mount, which is normal ext4
# behaviour) and repairs the inconsistencies that preen mode may fix safely. Every line it prints
# goes to the kernel log (dmesg | grep GoboRefined), so a check that did something is visible.
fsck_out=$(e2fsck -p "$DATADEV" 2>&1)
rc=$?
printf '%s\n' "$fsck_out" | while IFS= read -r line
do [ -n "$line" ] && say "  e2fsck: $line"
done
say "data partition check: e2fsck exit $rc"
[ $rc -ge 4 ] && say "the data partition has errors e2fsck could not fix; trying anyway"
mount -t ext4 -o rw,noatime "$DATADEV" $G/data || fail "cannot mount the data partition $DATADEV"
mount -t ext4 -o ro "$SLOTDEV" $G/slot || fail "cannot mount slot $SLOT ($SLOTDEV)"
fi
if [ ! -f $G/slot/gobo-slot.env ]
then
   umount $G/slot
   fail "slot $SLOT is empty or was not written completely; start the other slot"
fi
mkdir -p $O/install $O/upper $O/work

# --- reset of the system changes (requested by gobo-update --reset-system-changes) ---------------
if [ -e $O/reset-requested ]
then
   say "removing the system changes (kept: accounts; old changes in System-Overlay/previous-upper)"
   rm -rf $O/previous-upper $O/work
   mv $O/upper $O/previous-upper
   mkdir -p $O/upper/System/Settings $O/work
   for f in $ACCOUNTS
   do [ -e "$O/previous-upper/$f" ] && cp -a "$O/previous-upper/$f" "$O/upper/$f"
   done
   rm -f $O/reset-requested
   sync
fi

# --- first boot of a different system version: drop generated caches from the overlay ------------
version=$(sed -n '1p' "$G/slot/$SPIN_VERSION_FILE" 2>/dev/null | tr -dc '0-9A-Za-z.-')
last=$(sed -n '1p' $O/booted-version 2>/dev/null | tr -dc '0-9A-Za-z.-')
if [ "$MODE" = normal ] && [ "$version" != "$last" ]
then
   say "first start of system version ${version:-?} (last: ${last:-none}): clearing generated caches"
   if [ -f "$G/slot/$CACHE_LIST" ]
   then
      # Entries: absolute paths, letters/digits/._+-/ and '*' only, no "..". Paths are resolved
      # inside the slot (they often run through /System/Index links) and must end up below
      # /Programs or /System; /Data/Variable entries are matched on the data partition.
      sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$G/slot/$CACHE_LIST" | while read -r p
      do
         [ -n "$p" ] || continue
         case "$p" in /*) ;; *) continue ;; esac
         case "$p" in *..*|*[!A-Za-z0-9._+/*-]*) say "  skipped bad cache entry"; continue ;; esac
         case "$p" in
            /Data/Variable/*)
               for f in $G/data/Variable${p#/Data/Variable}
               do [ -e "$f" ] && rm -rf "$f"
               done
               ;;
            /Programs/*|/System/*)
               chroot $G/slot /System/Index/bin/sh -c 'for f in '"$p"'; do [ -e "$f" ] && /System/Index/bin/readlink -f "$f"; done' 2>/dev/null |
               while read -r phys
               do
                  case "$phys" in /Programs/?*/?*|/System/?*/?*) ;; *) continue ;; esac
                  case "$phys" in *..*|*[!A-Za-z0-9._+/-]*) continue ;; esac
                  rm -rf "$O/install$phys" "$O/upper$phys"
               done
               ;;
         esac
      done
   fi
   echo "$version" > $O/booted-version
   echo "$version" > $O/first-boot-pending
   sync
fi

# --- the overlay ----------------------------------------------------------------------------------
if [ "$MODE" = safe ]
then
   say "starting slot $SLOT WITHOUT the system changes (changes go to memory and are lost)"
   mount -t tmpfs -o mode=0755 goboab-mem $G/mem || fail "cannot mount a tmpfs"
   mkdir -p $G/mem/upper/System/Settings $G/mem/work
   # The accounts as they are now, so the user can log in (passwords changed after the install).
   for f in $ACCOUNTS
   do [ -e "$O/upper/$f" ] && cp -a "$O/upper/$f" "$G/mem/upper/$f"
   done
   upper=$G/mem/upper
   work=$G/mem/work
else
   upper=$O/upper
   work=$O/work
fi
mount -t overlay goboab-root \
   -o "lowerdir=$O/install:$G/slot,upperdir=$upper,workdir=$work,redirect_dir=off,index=off,metacopy=off" \
   "$NEWROOT" || fail "cannot mount the overlay root"

for d in Users Variable
do mkdir -p $G/data/$d
done
mount --bind $G/data/Users "$NEWROOT/Users" || fail "cannot mount /Users"
mount --bind $G/data/Variable "$NEWROOT/Data/Variable" || fail "cannot mount /Data/Variable"
if [ -n "${SWAPVOL:-}" ]
then
   mkdir -p "$NEWROOT/Data/Variable/swap"
   mount --move $G/swap "$NEWROOT/Data/Variable/swap" || say "cannot mount @swap at /Data/Variable/swap"
fi
# For gobo-update (status, reset flag, booted version) and for looking at the slot itself.
[ -d "$NEWROOT/System/Data" ] && mount --move $G/data "$NEWROOT/System/Data"
[ -d "$NEWROOT/System/Slot" ] && mount --move $G/slot "$NEWROOT/System/Slot"
say "root assembled: slot $SLOT (${version:-?}), $MODE mode"
exit 0
