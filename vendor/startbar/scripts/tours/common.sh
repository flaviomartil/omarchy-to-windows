# shellcheck shell=bash
# What StartBar's tours share (scripts/tours/*.sh source it): the sandbox they run in, the Dock they start with, and a few helpers
# for finding things in it. A tour file sets what is its own (TOUR_OUT, TOUR_STEPS, ...) and defines tour_play.
#
# The tour runs in a nested session (scripts/nested/session.sh): its own Hyprland and Omarchy shell, with this checkout as the
# plugin, in a home of its own, behind a guard that refuses the Start menu's power commands. Nothing of yours is touched, and
# the recorder proves it (TOUR_REAL_UNCHANGED).
#
# The Dock starts from the state the README's pictures show: icons on the left, the theme's colours, the built-in Start menu, previews
# on, no clock, no badge, no auto-hide, and these Pins. The Pins are apps installed on the machine that records; tour_requires says
# which one is missing.

TOUR_TITLE=StartBar
TOUR_PLUGIN_ID=io.github.bmaltais.startbar
TOUR_PLUGIN_WIDGET=0       # a service: loaded, not put on the Omarchy bar
TOUR_SANDBOX_COPY=()       # nothing of the real config: the Dock's settings and Pins are in the sandbox's shell.json (below)
TOUR_SANDBOX_LINK=(.local/share/icons)
# The recorder proves the tour touched none of these (it fails the run if one changed).
TOUR_REAL_UNCHANGED=(.config/omarchy/shell.json .local/share/applications)

ID=io.github.bmaltais.startbar
TOUR_PINS=(org.gnome.Nautilus com.mitchellh.ghostty microsoft-edge com.microsoft.VSCode obsidian)
TOUR_PLUGIN_ENTRY=$(jq -cn --argjson pins "$(printf '%s\n' "${TOUR_PINS[@]}" | jq -R . | jq -sc .)" '{
  alignment: "left", colorScheme: "theme", showStart: true, startCommand: "builtin", startHoverOpen: false, showClock: false,
  showWorkspaceBadge: false, transparent: false, groupWindows: true, showPreviews: true, previewPeek: true, previewWarpPointer: false,
  autoHide: false, position: "bottom", reserveSpace: false, edgeSpacing: 12, pins: $pins, startPins: $pins}')

tour_requires() {
  local app missing=()
  for app in "${TOUR_PINS[@]}"; do
    [[ -f /usr/share/applications/$app.desktop ]] || missing+=("$app")
  done
  ((${#missing[@]} == 0)) || { echo "tour: these Pins of the tour are not installed here: ${missing[*]} (edit TOUR_PINS in scripts/tours/common.sh)" >&2; return 1; }
  command -v foot >/dev/null || { echo "tour: foot is needed (it stands in for the apps' windows)" >&2; return 1; }
}

# Keys are sent only while the Start menu or the settings window is up (the Start menu is part of the Dock's own surface, so it is
# not a layer of its own: the Dock says whether it is open).
# (The settings window is a layer of its own. settings_up is defined here, not with the recorder's helpers, so that tour_setup, which
# runs before they exist, can wait for the window.)
settings_up() { hyprctl layers -j | jq -e '[.. | .namespace? // empty] | any(. == "omarchy-startbar-settings")' >/dev/null 2>&1; }
tour_keys_ok() { settings_up || omarchy-shell "$ID" layout 2>/dev/null | jq -e '.menus.start != null' >/dev/null 2>&1; }

# ---- finding things: the Dock reports them (`omarchy-shell $ID layout`), in pixels of the session's screen ----------------------
layout() { omarchy-shell "$ID" layout 2>/dev/null; }

# item_center JQ-TEST: "X Y", the centre of the first Item the test picks, e.g. '.appId == "foot"'. Waits up to 5 s for it.
item_center() {
  local out i
  for i in $(seq 1 50); do
    out=$(layout | jq -r ".items[] | select($1) | \"\\(.x + .width / 2 | floor) \\(.y + .height / 2 | floor)\"" | head -n1)
    [[ -n $out ]] && { echo "$out"; return 0; }
    sleep 0.1
  done
  echo "tour: no Dock Item matches $1" >&2
  return 1
}

# menu_rect NAME: "X Y W H" of the open menu (start, item, bar, barSub, preview). Waits up to 5 s for it to open and to stop sliding.
menu_rect() {
  local out prev="" i
  for i in $(seq 1 50); do
    out=$(layout | jq -r ".menus.$1 // empty | \"\\(.x) \\(.y) \\(.width) \\(.height)\"")
    [[ -n $out && $out == "$prev" ]] && { echo "$out"; return 0; }
    prev=$out
    sleep 0.15
  done
  echo "tour: the $1 menu did not open" >&2
  return 1
}

# ---- windows to fill the Dock ------------------------------------------------------------------------------------------------
# pose CLASS TITLE COLOUR WORKSPACE: a terminal window that poses as an app of that class, so the Dock gives it that app's icon, and
# shows its title in big letters on a colour, which is what its Preview shows. It is moved to a workspace of its own (2 or more), so
# it stands in the Dock and in the Previews without covering the wallpaper of the workspace being filmed, and a peek (which shows the
# window's workspace) shows that window alone.
pose() {
  local class=$1 title=$2 bg=${3:-2a3550} ws=${4:-2} i addr
  foot -a "$class" -T "$title" -o main.font=monospace:size=26 -o colors-dark.background="$bg" -o colors-dark.foreground=f2f2f2 \
    -o colors-dark.alpha=1 sh -c "printf '\n\n  %s\n' '$title'; exec sleep 3600" >/dev/null 2>&1 &
  for i in $(seq 1 60); do
    addr=$(hyprctl clients -j | jq -r --arg c "$class" --arg t "$title" '.[] | select(.class == $c and .title == $t) | .address' | head -n1)
    [[ -n $addr ]] && break
    sleep 0.1
  done
  [[ -n $addr ]] || { echo "tour: the window $title did not open" >&2; return 1; }
  hyprctl dispatch "hl.dsp.window.move({ workspace = \"$ws\", follow = false, window = \"address:$addr\" })" >/dev/null
}

# close_windows CLASS: close every window of that class.
close_windows() {
  local a
  for a in $(hyprctl clients -j | jq -r --arg c "$1" '.[] | select(.class == $c) | .address'); do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null 2>&1 || true
  done
}

# The Start button, which `layout` does not list: on a bottom bar with icons on the left it is the same distance in from the edge as
# the Dock's first Item is from the Start menu (31 px at the default 12 px spacing), on the Items' middle line.
start_button() {
  local x y
  read -r x y < <(item_center 'true')
  echo "$((x - 25 - 22)) $y"
}

# settle_focus: nothing is focused, as on a workspace with no window. A window moved off the workspace in view stays the compositor's
# "active window" until focus changes, and the Dock would show it as active and put it back as the focus after every Preview peek,
# which switches the workspace the tour is filming.
settle_focus() {
  hyprctl dispatch 'hl.dsp.focus({ workspace = "5" })' >/dev/null
  sleep 0.3
  hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null
  sleep 0.3
}
