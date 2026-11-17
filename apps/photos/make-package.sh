#!/bin/sh
# Makes the GoboLinux package of Photos (for Settings > Software > Apps):
#   sh make-package.sh [OUTPUT-DIR]     -> Photos--<version>--x86_64.tar.bz2
# Run it on a Linux system (file modes matter); the package holds only scripts.
set -e
V=1.1
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here}
t=$(mktemp -d)
P=$t/Photos/$V
mkdir -p $P/bin $P/share/gobo-photos $P/share/applications $P/Resources
install -m 755 $here/gobo-photos $P/bin/gobo-photos
install -m 644 $here/photos.lua $P/share/gobo-photos/photos.lua
install -m 644 $here/gobo-photos.desktop $P/share/applications/gobo-photos.desktop
echo x86_64 > $P/Resources/Architecture
printf '%s\n' 'FFmpeg >= 4.0' 'GTK+ >= 3.20' 'Lua >= 5.3' > $P/Resources/Dependencies
printf '%s\n' '[Name] Photos' "[Version] $V" '[Summary] Pictures and videos in one simple window' '[License] MIT' \
   '[Description] A small viewer for GoboRefined: JPEG, PNG and other pictures, MP4 and other videos (played through FFmpeg).' \
   '[Homepage] https://github.com/landlubber2' > $P/Resources/Description
tar -cjf "$out/Photos--$V--x86_64.tar.bz2" --owner=0 --group=0 -C $t Photos
rm -rf $t
echo "$out/Photos--$V--x86_64.tar.bz2"
