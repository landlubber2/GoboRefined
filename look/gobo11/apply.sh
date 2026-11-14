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
# Terminal: right click pastes (perl extension, loaded via URxvt.perl-ext-common)
mkdir -p "$home/.urxvt/ext"
cp "$here/urxvt/gobo-paste" "$home/.urxvt/ext/gobo-paste"
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
# Clipboard history (CopyQ, 0.6): 20 items, no tray icon, keeps the clipboard when its
# program closes; kept if the user already has settings of their own.
for conf in copyq/copyq.conf copyq/copyq-commands.ini
do
   if [ ! -e "$home/.config/$conf" ]
   then
      mkdir -p "$home/.config/copyq"
      cp "$here/$conf" "$home/.config/$conf"
   fi
done
# Office documents open in ONLYOFFICE (kept if the user already has their own list)
if [ ! -e "$home/.config/mimeapps.list" ]
then cp "$here/xdg/mimeapps.list" "$home/.config/mimeapps.list"
fi
# File manager side pane: a "USB drives" entry (devmon mounts sticks under /Mount/Media)
if [ ! -e "$home/.config/gtk-3.0/bookmarks" ]
then echo "file:///Mount/Media USB drives" > "$home/.config/gtk-3.0/bookmarks"
fi
# Standard folders (0.6) and their XDG names, used by the GTK file chooser, PCManFM and
# the screenshot tool. Run on the skeleton by the ISO build, so the live user and every
# new user get them; an existing user-dirs.dirs is kept.
for d in Desktop Documents Downloads Music Pictures Pictures/Screenshots Videos
do mkdir -p "$home/$d"
done
if [ ! -e "$home/.config/user-dirs.dirs" ]
then
   cat > "$home/.config/user-dirs.dirs" <<'DIRS'
# Written by the GoboRefined look (apply.sh). Format: XDG_xxx_DIR="$HOME/yyy"
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_TEMPLATES_DIR="$HOME/"
XDG_PUBLICSHARE_DIR="$HOME/"
DIRS
fi
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
