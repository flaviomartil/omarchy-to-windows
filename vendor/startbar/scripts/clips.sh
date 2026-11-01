#!/bin/bash
# Records the README's clips (scripts/tours/*-clip.sh) and installs them in screenshots/. Each one is its own session, so this takes a
# few minutes. See docs/recording-tours.md ("Clips of one window").
#
#   scripts/clips.sh [CLIP...]     CLIP is taskbar, icon-menu, start-menu, bar-menu or settings (default: all five)
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
clips=("$@")
((${#clips[@]})) || clips=(taskbar icon-menu start-menu bar-menu settings)
for c in "${clips[@]}"; do
  [[ -f $HERE/tours/$c-clip.sh ]] || { echo "clips: no clip called $c" >&2; exit 2; }
  "$HERE/tour.sh" "$HERE/tours/$c-clip.sh" --install
done
