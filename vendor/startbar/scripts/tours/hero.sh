# shellcheck shell=bash
# StartBar's tour: the animation at the top of the README (screenshots/hero.avif).
# Run it with scripts/tour.sh scripts/tours/hero.sh --install (or scripts/hero.sh --install).
#
# The story: hover a group of windows for its Preview and a thumbnail for a peek; right-click an icon for its menu; search the Start
# menu and launch an app; right-click the bar and open a submenu; the settings window, a search, another page, and the bar following
# the colours and the edge chosen there; then the Dock on the left in the light colours, with the Start menu and a Preview.
#
# It runs in a nested session in a sandbox (scripts/tours/common.sh): nothing of yours is touched, and the Start menu's power
# commands are refused. The windows in the Dock are terminals posing as apps (the Dock gives them those apps' icons).
#
# Coordinates in the settings window are those of the window at its default size and place, centred on the 1280x800 screen
# (Service.qml, settingsWindow): the search box at the top, the page list on the left, then the rows of the Taskbar page.

# shellcheck source=tours/common.sh
source "$HERE/tours/common.sh"
TOUR_OUT=screenshots/hero.avif
TOUR_STEPS=6
TOUR_MAX_SECONDS=360

tour_setup() {
  pose org.gnome.Nautilus "Documents" 2a3550 2
  pose org.gnome.Nautilus "Downloads" 3d3a52 3
  pose com.mitchellh.ghostty "Terminal" 1f3b2d 4
  pose btop "btop" 4a2f3a 5
  item_center '.appId == "btop"' >/dev/null
  settle_focus
}

tour_play() {
  local x y bx by bw bh px py pw ph

  # 1. The Preview of a group of windows, and a peek.
  cap "Hover an icon for a live preview of each window"
  glide 640 400
  read -r x y < <(item_center '.appId == "org.gnome.Nautilus"')
  glide "$x" "$((y - 40))"; glide "$x" "$y"
  read -r px py pw ph < <(menu_rect preview)
  sleep 1.6
  glide "$((px + pw / 4))" "$((py + ph / 2))"; sleep 2.0
  glide "$((px + pw * 3 / 4))" "$((py + ph / 2))"; sleep 2.0
  glide 640 300; sleep 1.0

  # 2. An icon's menu.
  cap "Right-click an icon for its menu"
  read -r x y < <(item_center '.appId == "btop"')
  rclick "$x" "$y" 0.6
  read -r bx by bw bh < <(menu_rect item)
  sleep 1.2
  glide "$((bx + bw / 2))" "$((by + bh * 2 / 10))"; sleep 1.4
  glide "$((bx + bw / 2))" "$((by + bh * 8 / 10))"; sleep 1.8
  click 700 300 1.0

  # 3. The Start menu: search for an app and launch it.
  cap "Search the Start menu and launch any app"
  read -r x y < <(start_button)
  click "$x" "$y" 1.2
  menu_rect start >/dev/null
  typed "foot"; sleep 1.6
  pressed Return
  wait_until "hyprctl clients -j | jq -e '.[] | select(.class == \"foot\")'" 20
  sleep 2.6
  close_windows foot
  sleep 1.2

  # 4. The Bar menu and a submenu, then its last row opens the settings window.
  cap "Right-click the bar for quick options"
  rclick 640 "$y" 1.0
  read -r bx by bw bh < <(menu_rect bar)
  sleep 1.2
  glide "$((bx + bw / 2))" "$((by + 4 + 32 + 16))"; menu_rect barSub >/dev/null; sleep 2.0     # Position
  glide "$((bx + bw / 2))" "$((by + 4 + 96 + 9 + 16))"; menu_rect barSub >/dev/null; sleep 1.6  # Start button
  glide "$((bx + bw / 2))" "$((by + bh - 20))"; sleep 0.6
  click "$((bx + bw / 2))" "$((by + bh - 20))" 1.4                                              # Settings...

  # 5. The settings window: a search, another page, then colours and the edge, which the bar follows at once.
  cap "Every setting in one window, with search. Changes apply as you click"
  click 640 120 0.5
  typed "icon"; sleep 2.2
  pressed BackSpace; sleep 0.12; pressed BackSpace; sleep 0.12; pressed BackSpace; sleep 0.12; pressed BackSpace
  sleep 0.8
  click 299 253 1.6          # Windows
  click 299 213 1.2          # Taskbar
  click 987 293 2.0          # Colors: Light
  click 889 251 2.2          # Position: Left
  esc; sleep 1.2

  # 6. The Dock on the left, in the light colours: the Start menu, and a Preview beside it.
  cap "Any edge, light or dark. Here it is on the left"
  read -r x y < <(item_center 'true')
  click "$x" "$((y - 52))" 1.2
  menu_rect start >/dev/null
  typed "set"; sleep 2.0
  esc; sleep 0.5; esc; sleep 0.8
  read -r x y < <(item_center '.appId == "org.gnome.Nautilus"')
  glide 3 "$y"; glide "$x" "$y"
  read -r px py pw ph < <(menu_rect preview)
  sleep 2.4
  glide "$((px + pw / 4))" "$((py + ph / 2))"; sleep 2.0
  glide 700 300; sleep 1.2
}
