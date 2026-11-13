#!/bin/sh
# Apply the gobo11 look to one user's home directory.
#   apply.sh [HOME_DIR] [XKB_LAYOUT]
# Run as that user (or as root, then fix ownership). The stock Awesome config
# is kept next to the new one as ~/.config/awesome.stock.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
home="${1:-$HOME}"
layout="${2:-}"

mkdir -p "$home/.config"
if [ -d "$home/.config/awesome" ] && [ ! -d "$home/.config/awesome.stock" ]
then cp -a "$home/.config/awesome" "$home/.config/awesome.stock"
fi
mkdir -p "$home/.config/awesome" "$home/.config/gtk-3.0"
cp -r "$here/awesome/." "$home/.config/awesome/"
cp "$here/picom.conf" "$home/.config/picom.conf"
cp "$here/gtk-3.0/settings.ini" "$home/.config/gtk-3.0/settings.ini"
mkdir -p "$home/.config/fontconfig"
cp "$here/fontconfig/fonts.conf" "$home/.config/fontconfig/fonts.conf"
# File manager defaults (PCManFM/libfm); kept if the user already has their own.
for conf in libfm/libfm.conf pcmanfm/default/pcmanfm.conf
do
   if [ ! -e "$home/.config/$conf" ]
   then
      mkdir -p "$(dirname "$home/.config/$conf")"
      cp "$here/$conf" "$home/.config/$conf"
   fi
done
# Keep the keyboard layout the user already had unless one is given.
if [ -z "$layout" ] && [ -e "$home/.xinitrc" ]
then layout=$(sed -n 's/^setxkbmap .*-layout \([a-z,]*\).*/\1/p' "$home/.xinitrc" | head -n 1)
fi
sed "s|^setxkbmap .*|setxkbmap -model pc104 -layout ${layout:-us}|" "$here/xinitrc" > "$home/.xinitrc"

touch "$home/.Xresources"
# Replace an older copy of the gobo11 block (it runs from its first line to
# "end of gobo11 look", or to the end of the file for blocks written before
# that marker existed), then append the current one.
if grep -q 'gobo11 look (appended' "$home/.Xresources"
then
   if grep -q 'end of gobo11 look' "$home/.Xresources"
   then sed -i '/gobo11 look (appended/,/end of gobo11 look/d' "$home/.Xresources"
   else sed -i '/gobo11 look (appended/,$d' "$home/.Xresources"
   fi
fi
cat "$here/Xresources.append" >> "$home/.Xresources"
echo "gobo11 look applied to $home (log out and back in to see all of it)"
