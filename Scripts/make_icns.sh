#!/bin/bash
# Needs macOS + `brew install librsvg`.
set -e; cd "$(dirname "$0")/.."; set=Design/Sono.iconset; mkdir -p $set
for s in 16 32 128 256 512; do
  rsvg-convert -w $s -h $s Design/Sono.svg -o $set/icon_${s}x${s}.png
  rsvg-convert -w $((s*2)) -h $((s*2)) Design/Sono.svg -o $set/icon_${s}x${s}@2x.png
done
iconutil -c icns $set -o Design/Sono.icns
