#!/usr/bin/env bash
# Lab helper (0.8): drive the VM console without the clipboard.
#   vm/vbox-keys.sh shot NAME          screenshot to the scratch dir given by $SHOTS (default: $TEMP)
#   vm/vbox-keys.sh tty N              Ctrl+Alt+F<N>
#   vm/vbox-keys.sh type 'text'        type text (no newline); \n is Enter
#   vm/vbox-keys.sh enter
#   vm/vbox-keys.sh rootpw             type the lab root password from vm/serve/lab-answers.env + Enter
#                                      (never printed)
#   vm/vbox-keys.sh userpw             same for the lab user's password
set -e
export MSYS_NO_PATHCONV=1
export PATH="$PATH:/c/Program Files/Oracle/VirtualBox"
VM=GoboLinux-017.01
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHOTS="${SHOTS:-$TEMP}"
case "$1" in
   shot)  VBoxManage controlvm $VM screenshotpng "$(cygpath -w "$SHOTS")\\$2.png" ;;
   tty)   f=$((0x3a + $2)); f=$(printf '%02x' $f); b=$(printf '%02x' $((0x$f + 0x80)))
          VBoxManage controlvm $VM keyboardputscancode 1d 38 $f $b b8 9d ;;
   type)  VBoxManage controlvm $VM keyboardputstring "$2" ;;
   enter) VBoxManage controlvm $VM keyboardputscancode 1c 9c ;;
   rootpw|userpw)
          var=ROOT_PASSWORD; [ "$1" = userpw ] && var=USER_PASSWORD
          pw=$(sed -n "s/^$var=//p" "$here/serve/lab-answers.env" | sed -e "s/^['\"]//" -e "s/['\"]\$//")
          VBoxManage controlvm $VM keyboardputstring "$pw" > /dev/null
          VBoxManage controlvm $VM keyboardputscancode 1c 9c ;;
   *) echo "usage: see header" >&2; exit 1 ;;
esac
