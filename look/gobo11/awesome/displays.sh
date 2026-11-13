#!/bin/sh
# Extend the desktop across all connected displays, left to right, each at its
# preferred resolution. Runs at login; also in the menu as "Detect Displays".
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
