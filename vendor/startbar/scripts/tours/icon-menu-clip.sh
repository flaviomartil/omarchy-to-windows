# shellcheck shell=bash
# A short clip of an icon's right-click menu, cropped from the session: a running app's menu, then a pinned app's, ending on the idle Dock so
# that the animation loops. Run it with scripts/tour.sh scripts/tours/icon-menu-clip.sh [--install].
#
# It runs in a sandbox, like the hero tour (see scripts/tours/common.sh).

# shellcheck source=tours/common.sh
source "$HERE/tours/common.sh"
TOUR_OUT=screenshots/icon-menu-clip.avif
# The Dock and the menus that rise from it, over the theme's wallpaper, with a margin.
TOUR_CROP=640x340+0+460
TOUR_MAX_SECONDS=120

tour_setup() {
  pose btop "btop" 4a2f3a 2
  item_center '.appId == "btop"' >/dev/null
  settle_focus
}

tour_play() {
  local x y mx my mw mh
  glide 500 560; sleep 1.0
  # A running app that is not pinned: its actions, the window's state, Close window, then the app and Pin to taskbar.
  read -r x y < <(item_center '.appId == "btop"')
  rclick "$x" "$y" 0.6
  read -r mx my mw mh < <(menu_rect item)
  sleep 1.0
  glide "$((mx + mw / 2))" "$((my + mh * 2 / 10))"; sleep 1.4
  glide "$((mx + mw / 2))" "$((my + mh * 8 / 10))"; sleep 1.6
  click 560 520 1.2
  # A pinned app that is not running: its actions, the app, Unpin from taskbar.
  read -r x y < <(item_center '.appId == "microsoft-edge"')
  rclick "$x" "$y" 0.6
  read -r mx my mw mh < <(menu_rect item)
  sleep 1.0
  glide "$((mx + mw / 2))" "$((my + mh * 7 / 10))"; sleep 1.8
  click 560 520 1.2
  glide 500 560; sleep 0.8
}
