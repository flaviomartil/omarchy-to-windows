# shellcheck shell=bash
# A short clip of the taskbar, cropped from the session: the pointer goes over the Items and rests on a group of windows for its
# Preview, then on one thumbnail, which peeks that window; it ends on the idle Dock, so that the animation loops. A clip like this
# replaces a still image in the README. Run it with scripts/tour.sh scripts/tours/taskbar-clip.sh [--install].
#
# It runs in a sandbox, like the hero tour (see scripts/tours/common.sh).

# shellcheck source=tours/common.sh
source "$HERE/tours/common.sh"
TOUR_OUT=screenshots/taskbar-clip.avif
# The Dock and the Preview that rises from it, over the theme's wallpaper, with a margin.
TOUR_CROP=640x260+0+540
TOUR_MAX_SECONDS=120

tour_setup() {
  pose org.gnome.Nautilus "Documents" 2a3550 2
  pose org.gnome.Nautilus "Downloads" 3d3a52 3
  pose com.mitchellh.ghostty "Terminal" 1f3b2d 4
  pose btop "btop" 4a2f3a 5
  item_center '.appId == "btop"' >/dev/null
  settle_focus
}

tour_play() {
  local x y px py pw ph
  glide 400 640; sleep 1.2
  # Over the Items, one by one.
  read -r x y < <(item_center '.appId == "com.mitchellh.ghostty"')
  glide "$x" "$((y - 30))"; glide "$x" "$y"; sleep 1.4
  # The group of two windows: its Preview, then a thumbnail.
  read -r x y < <(item_center '.appId == "org.gnome.Nautilus"')
  glide "$x" "$y"
  read -r px py pw ph < <(menu_rect preview)
  sleep 1.6
  glide "$((px + pw / 4))" "$((py + ph / 2))"; sleep 1.8
  glide "$((px + pw * 3 / 4))" "$((py + ph / 2))"; sleep 1.8
  glide 400 640; sleep 1.2
}
