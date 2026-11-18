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
# 0.9.6: file manager action "Pin to start" (files and folders in the start menu's panel)
mkdir -p "$home/.local/share/file-manager/actions"
cp "$here/file-manager/actions/gobo-pin-to-start.desktop" "$home/.local/share/file-manager/actions/"
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
# 0.8.1: plain text opens in L3afpad, also in lists made before 0.8.1 (unless the user chose one)
if ! grep -q '^text/plain=' "$home/.config/mimeapps.list"
then
   if grep -q '^\[Default Applications\]' "$home/.config/mimeapps.list"
   then sed -i 's|^\[Default Applications\]$|&\ntext/plain=l3afpad.desktop|' "$home/.config/mimeapps.list"
   else printf '[Default Applications]\ntext/plain=l3afpad.desktop\n' >> "$home/.config/mimeapps.list"
   fi
fi
# File manager side pane: "USB drives" is a fixed entry of the spin's LibFM since 0.6 (last of
# the places, drive icon, mounted sticks listed below it). 0.5 wrote it as a bookmark: remove
# that line, keep the user's own bookmarks.
bm="$home/.config/gtk-3.0/bookmarks"
if [ -f "$bm" ] && grep -qx 'file:///Mount/Media USB drives' "$bm"
then
   grep -vx 'file:///Mount/Media USB drives' "$bm" > "$bm.tmp" || true
   if [ -s "$bm.tmp" ]; then mv -f "$bm.tmp" "$bm"; else rm -f "$bm.tmp" "$bm"; fi
fi
# Standard folders (0.6) and their XDG names, used by the GTK file chooser, PCManFM and
# the screenshot tool. Run on the skeleton by the ISO build, so the live user and every
# new user get them; an existing user-dirs.dirs is kept.
for d in Desktop Documents Downloads Music Pictures Pictures/Screenshots Videos
do mkdir -p "$home/$d"
done
# Trash icon on the desktop (0.6): opens the Trash window (gobo-trash: restore, empty, automatic
# clean-up after 1/3/6 months). Written once; a user who deletes it does not get it back.
if [ ! -e "$home/.config/gobo11-trash-icon" ]
then
   cat > "$home/Desktop/Trash.desktop" <<'TRASH'
[Desktop Entry]
Type=Application
Name=Trash
Comment=Restore deleted files, empty the Trash, choose when old items are deleted
Icon=user-trash
Exec=gobo-trash
Terminal=false
TRASH
   chmod 755 "$home/Desktop/Trash.desktop"
   echo "Trash.desktop was put on the desktop by apply.sh (0.6); delete this file to get it again." \
      > "$home/.config/gobo11-trash-icon"
fi
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
# 0.8.1: layout "system" (the skeleton, i.e. users added after the install) = the layout chosen
# at install time, read at login by system_layout in the xinitrc.
if [ -z "$layout" ] && [ -e "$home/.xinitrc" ]
then
   if grep -q '^setxkbmap .*system_layout' "$home/.xinitrc"
   then layout=system
   else layout=$(sed -n 's/^setxkbmap .*-layout \([a-z,]*\).*/\1/p' "$home/.xinitrc" | head -n 1)
   fi
fi
if [ "$layout" = system ]
then sed 's|^setxkbmap .*|setxkbmap -model pc104 -layout "$(system_layout)"|' "$here/xinitrc" > "$home/.xinitrc"
else sed "s|^setxkbmap .*|setxkbmap -model pc104 -layout ${layout:-us}|" "$here/xinitrc" > "$home/.xinitrc"
fi

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
# 0.8: apply.sh runs again for every home after a system update. The GTK settings were just
# replaced by the dark defaults: put back the colour mode the user chose (power menu).
if [ -f "$home/.config/awesome/mode" ] && [ "$(cat "$home/.config/awesome/mode")" = light ]
then HOME="$home" sh "$home/.config/awesome/set-mode.sh" light
fi
# 0.9.1: Simple accounts (group "simple"): the file manager's side pane lists Home, Desktop, the
# standard folders, USB drives and the Trash, not the file system (the spin's PCManFM refuses other
# places for them anyway). Marker ~/.config/goborefined/simple-layout: undone when the account
# becomes standard or administrator again (bookmarks only if they are still the ones written here).
owner=$(stat -c %U "$home" 2>/dev/null || true)
marker="$home/.config/goborefined/simple-layout"
lconf="$home/.config/libfm/libfm.conf"
simple_bm() {
   for d in Documents Downloads Pictures Music Videos
   do echo "file://$home/$d $d"
   done
}
is_simple=0
if [ -n "$owner" ] && [ "$owner" != root ] && id -Gn "$owner" 2>/dev/null | tr ' ' '\n' | grep -qx simple
then is_simple=1
fi
if [ "$is_simple" = 1 ]
then
   mkdir -p "$home/.config/goborefined"
   if [ -f "$lconf" ]
   then sed -i -e 's/^places_root=.*/places_root=0/' -e 's/^places_trash=.*/places_trash=1/' \
               -e 's/^places_computer=.*/places_computer=0/' -e 's/^places_network=.*/places_network=0/' \
               -e 's/^places_applications=.*/places_applications=0/' -e 's/^places_unmounted=.*/places_unmounted=0/' "$lconf"
   fi
   [ -e "$bm" ] || simple_bm > "$bm"
   echo "Simple account layout written by apply.sh (0.9.1)" > "$marker"
elif [ -e "$marker" ]
then
   if [ -f "$lconf" ]
   then sed -i -e 's/^places_root=.*/places_root=1/' -e 's/^places_trash=.*/places_trash=0/' "$lconf"
   fi
   if [ -f "$bm" ] && [ "$(cat "$bm")" = "$(simple_bm)" ]; then rm -f "$bm"; fi
   rm -f "$marker"
fi
# Which spin version's look this home has (share/spin-version next to share/gobo11 on the image).
if [ -f "$here/../spin-version" ]
then head -n 1 "$here/../spin-version" > "$home/.config/awesome/look-version"
fi
echo "gobo11 look applied to $home (log out and back in to see all of it)"
