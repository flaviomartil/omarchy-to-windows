# shellcheck shell=bash
# A short clip of the settings window, cropped from the session: the pages are flipped through, a search lists the matching settings, and
# one switch is flipped and flipped back, ending where it began so that the animation loops. A clip like this replaces a still image in
# the README. Run it with scripts/tour.sh scripts/tours/settings-clip.sh [--install].
#
# It runs in a sandbox, like the hero tour (see scripts/tours/common.sh). The coordinates are those of the window at its default size and
# place, centred on the 1280x800 screen: the search box at the top, the page list on the left, the rows of the Taskbar page.

# shellcheck source=tours/common.sh
source "$HERE/tours/common.sh"
TOUR_OUT=screenshots/settings-clip.avif
# The settings window, centred on the screen, with a 30 px margin of wallpaper.
TOUR_CROP=840x680+220+60
TOUR_MAX_SECONDS=150

# The window is already open when filming starts, so the clip begins and ends on the same picture.
tour_setup() {
  omarchy-shell "$ID" settings
  for _ in $(seq 1 40); do settings_up && break; sleep 0.5; done
  settings_up || { echo "tour: the settings window did not open" >&2; return 1; }
  sleep 1.5
}

tour_play() {
  glide 640 400; sleep 1.2
  click 299 253 1.6          # Windows
  click 310 293 1.6          # Start menu
  click 299 213 1.4          # Taskbar
  click 640 120 0.5          # the search box
  typed "icon"; sleep 2.0
  pressed BackSpace; sleep 0.12; pressed BackSpace; sleep 0.12; pressed BackSpace; sleep 0.12; pressed BackSpace
  sleep 0.8
  click 989 534 1.4          # Clock: on
  click 989 534 1.4          # and off again
  glide 640 400; sleep 0.8
}
