#!/bin/sh
# Extend the desktop across all connected displays, left to right, each at its
# preferred resolution. Runs at login; also in the menu as "Detect Displays" (--auto).
# At login, a layout saved with the "Displays..." window (LxRandr writes it to
# ~/.config/autostart/lxrandr-autostart.desktop) is used instead, if there is one.
saved="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/lxrandr-autostart.desktop"
if [ "$1" != "--auto" ] && [ -f "$saved" ]
then
   cmd=$(sed -n 's/^Exec=//p' "$saved" | head -n 1)
   if [ -n "$cmd" ] && eval "$cmd"
   then exit 0
   fi
fi
prev=""
for out in $(xrandr --query | awk '$2 == "connected" { print $1 }')
do
   if [ -z "$prev" ]
   then xrandr --output "$out" --auto --primary
   else xrandr --output "$out" --auto --right-of "$prev"
   fi
   prev="$out"
done
for out in $(xrandr --query | awk '$2 == "disconnected" { print $1 }')
do xrandr --output "$out" --off
done
