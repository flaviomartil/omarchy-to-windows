#!/usr/bin/env bash
# Compose preview.png, the marketplace's picture of StartBar, from the shots in
# screenshots/: the Start menu, the settings window, the Bar menu with a
# submenu open, a hover Preview and the Dock, on a dark gradient with the name
# and a badge for the Omarchy release it is compatible with.
#
#   scripts/make-preview.sh [OUT]      (default: preview.png at the repo root)
#
# Needs ImageMagick. Retake the shots first (scripts/screenshots.sh) if the
# look changed: the crops below follow their margins, so a changed shot may
# need new numbers.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
shots=$repo/screenshots
out=${1:-$repo/preview.png}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
font=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf
[[ -f $font ]] || font=DejaVu-Sans-Bold

# card IN OUT GEOMETRY SCALE%: crop, scale, round the corners and add a shadow.
card() {
  local in=$1 dest=$2 crop=$3 scale=$4 w h
  magick "$in" -crop "$crop" +repage -resize "$scale%" "$work/c.png"
  w=$(magick identify -format %w "$work/c.png"); h=$(magick identify -format %h "$work/c.png")
  magick "$work/c.png" -alpha set \
    \( -size "${w}x${h}" xc:none -fill white -draw "roundrectangle 0,0 $((w - 1)),$((h - 1)) 9,9" \) \
    -compose DstIn -composite "$work/r.png"
  shadow "$work/r.png" "$dest"
}

shadow() {
  magick "$1" \( +clone -background black -shadow 70x22+0+16 \) +swap -background none -layers merge +repage "$2"
}

card "$shots/start-menu.png" "$work/start.png" 748x638+13+34 84
card "$shots/settings.png" "$work/settings.png" 776x616+34+34 88
card "$shots/preview.png" "$work/preview.png" 468x208+14+30 88
card "$shots/taskbar.png" "$work/dock.png" 790x50+0+24 100

# The Bar menu and its submenu are two rounded shapes in one shot: cut both out.
magick "$shots/right-click-submenu.png" -alpha set \
  \( -size 527x451 xc:none -fill white \
     -draw "roundrectangle 33,33 270,418 9,9" -draw "roundrectangle 272,138 495,272 9,9" \) \
  -compose DstIn -composite -trim +repage -resize 92% "$work/r.png"
shadow "$work/r.png" "$work/menus.png"

# The badge above the name: a pill sized to its text.
magick -background none -fill '#e8dcff' -font "$font" -pointsize 21 \
  label:"Compatible with Omarchy 4.5 windowed mode" -trim +repage "$work/badge-text.png"
bw=$(( $(magick identify -format %w "$work/badge-text.png") + 36 ))
bh=$(( $(magick identify -format %h "$work/badge-text.png") + 18 ))
magick -size "${bw}x${bh}" xc:none -fill 'rgba(255,255,255,0.13)' -draw "roundrectangle 0,0 $((bw - 1)),$((bh - 1)) $((bh / 2)),$((bh / 2))" \
  -stroke 'rgba(205,188,245,0.45)' -strokewidth 1 -fill none -draw "roundrectangle 0,0 $((bw - 1)),$((bh - 1)) $((bh / 2)),$((bh / 2))" \
  "$work/badge-text.png" -gravity center -compose over -composite "$work/badge.png"

magick -size 1600x900 radial-gradient:'#2a1650-#0a0816' \
  \( -size 1100x1100 radial-gradient:'rgba(226,72,128,0.55)-rgba(226,72,128,0)' \) -geometry +900-420 -compose plus -composite \
  \( -size 1000x1000 radial-gradient:'rgba(86,120,255,0.40)-rgba(86,120,255,0)' \) -geometry -380+420 -compose plus -composite \
  -compose over \
  -font "$font" -fill white -pointsize 84 -annotate +72+150 "StartBar" \
  -fill '#cdbcf5' -pointsize 30 -annotate +76+205 "A taskbar with a Start menu for Omarchy" \
  "$work/badge.png" -geometry +76+30 -composite \
  "$work/settings.png" -geometry +836+60 -composite \
  "$work/start.png" -geometry +50+236 -composite \
  "$work/preview.png" -geometry +650+640 -composite \
  "$work/menus.png" -geometry +1110+505 -composite \
  "$work/dock.png" -geometry +50+812 -composite \
  "$out"

echo "make-preview: wrote $out ($(magick identify -format '%wx%h' "$out"))"
