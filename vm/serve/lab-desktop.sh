# Lab helper (runs in the VM as root): run Lua in the logged-in user's desktop.
#   sh lab-desktop.sh LOGIN 'lua code'
login="$1"; code="$2"
pid=$(pgrep -u "$login" -x awesome | head -n 1)
[ -n "$pid" ] || { echo "awesome is not running for $login"; exit 1; }
disp=$(tr '\0' '\n' < /proc/$pid/environ | sed -n 's/^DISPLAY=//p')
su "$login" -c "DISPLAY=$disp DBUS_SESSION_BUS_ADDRESS= awesome-client '$code'" 2>&1 | tail -n 2
