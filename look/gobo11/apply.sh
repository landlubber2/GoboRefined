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

# Keep the keyboard layout the user already had unless one is given.
if [ -z "$layout" ] && [ -e "$home/.xinitrc" ]
then layout=$(sed -n 's/^setxkbmap .*-layout \([a-z,]*\).*/\1/p' "$home/.xinitrc" | head -n 1)
fi
sed "s|^setxkbmap .*|setxkbmap -model pc104 -layout ${layout:-us}|" "$here/xinitrc" > "$home/.xinitrc"

touch "$home/.Xresources"
if ! grep -q 'gobo11 look' "$home/.Xresources"
then cat "$here/Xresources.append" >> "$home/.Xresources"
fi
echo "gobo11 look applied to $home (log out and back in to see all of it)"
