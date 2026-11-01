# shellcheck shell=bash
# A short clip of the bar's right-click menu, cropped from the session: it opens on an empty part of the bar and the pointer goes down
# its rows, each section opening a submenu beside it; the click outside closes it, so that the animation loops. Run it with
# scripts/tour.sh scripts/tours/bar-menu-clip.sh [--install].
#
# It runs in a sandbox, like the hero tour (see scripts/tours/common.sh). Nothing is chosen, so the settings stay as they were.

# shellcheck source=tours/common.sh
source "$HERE/tours/common.sh"
TOUR_OUT=screenshots/bar-menu-clip.avif
# The Dock and the menu with its submenu rising from it, over the theme's wallpaper, with a margin.
TOUR_CROP=760x460+360+340
TOUR_MAX_SECONDS=120

tour_play() {
  local x y bx by bw bh
  glide 700 500; sleep 1.0
  read -r x y < <(start_button)
  rclick 640 "$y" 1.0
  read -r bx by bw bh < <(menu_rect bar)
  sleep 1.2
  glide "$((bx + bw / 2))" "$((by + 4 + 16))"; menu_rect barSub >/dev/null; sleep 1.6        # Icon alignment
  glide "$((bx + bw / 2))" "$((by + 4 + 32 + 16))"; menu_rect barSub >/dev/null; sleep 1.6   # Position
  glide "$((bx + bw / 2))" "$((by + 4 + 64 + 16))"; menu_rect barSub >/dev/null; sleep 1.6   # Colors
  glide "$((bx + bw / 2))" "$((by + 4 + 96 + 9 + 16))"; menu_rect barSub >/dev/null; sleep 1.8   # Start button
  glide "$((bx + bw / 2))" "$((by + bh - 90))"; sleep 1.4                                       # the toggles
  click 700 500 1.0
  sleep 0.6
}
