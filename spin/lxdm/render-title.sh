#!/bin/sh
# Render the LXDM greeter title image (spin/lxdm/Gobo11/login.png) in the build VM:
#   sh render-title.sh /tmp/login.png   (ImageMagick and Inter are on the image)
F=/Programs/Inter/4.1/share/fonts/Inter
OUT=${1:-/tmp/login.png}
magick -size 560x132 xc:none \
  -font $F/Inter-Medium.ttf -pointsize 66 -fill white -gravity north -annotate +0+4 'GoboRefined' \
  -font $F/Inter-Regular.ttf -pointsize 19 -fill '#dce4ff' -gravity north -annotate +0+96 'an unofficial spin of GoboLinux 017.01' \
  \( +clone -background black -shadow 55x2+0+2 \) +swap -background none -layers merge +repage \
  -gravity center -extent 560x132 -depth 8 $OUT 2>&1 | grep -v 'configure file'
