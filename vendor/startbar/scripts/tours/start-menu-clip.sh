# shellcheck shell=bash
# A short clip of the Start menu, cropped from the session: it opens from the Start button, a search filters the apps, the arrow keys
# move, Escape backs out, All apps lists them A to Z, and it closes, so that the animation loops. Run it with
# scripts/tour.sh scripts/tours/start-menu-clip.sh [--install].
#
# It runs in a sandbox, like the hero tour (see scripts/tours/common.sh). Nothing is launched: the search ends with Escape.

# shellcheck source=tours/common.sh
source "$HERE/tours/common.sh"
TOUR_OUT=screenshots/start-menu-clip.avif
# The Start menu and the Dock under it, over the theme's wallpaper, with a margin.
TOUR_CROP=790x710+0+90
TOUR_MAX_SECONDS=150

tour_play() {
  local x y
  glide 500 400; sleep 1.0
  read -r x y < <(start_button)
  click "$x" "$y" 1.6
  menu_rect start >/dev/null
  sleep 1.0
  typed "fo"; sleep 1.6
  pressed Down; sleep 0.7
  pressed Down; sleep 1.2
  esc; sleep 1.2                       # clears the search
  # All apps, A to Z.
  click 712 182 1.4
  scroll 460 400 3 1.0
  scroll 460 400 -3 1.0
  esc; sleep 1.0                       # back to the Pinned grid
  esc; sleep 0.8                       # closes the menu
  glide 500 400; sleep 0.6
}
