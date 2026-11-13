#!/bin/sh
# Remember the chosen colour mode ("dark" or "light") for the desktop and GTK apps.
# The power menu calls this and then reloads the desktop.
mode="$1"
case "$mode" in dark|light) ;; *) echo "usage: set-mode.sh dark|light" >&2; exit 1 ;; esac
dir="$(cd "$(dirname "$0")" && pwd)"
echo "$mode" > "$dir/mode"
gtk="$HOME/.config/gtk-3.0/settings.ini"
if [ -f "$gtk" ]
then
   [ "$mode" = dark ] && dark=1 || dark=0
   sed -i "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=$dark/" "$gtk"
fi
