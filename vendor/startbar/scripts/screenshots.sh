#!/usr/bin/env bash
# Retake the README screenshots in the nested test session (scripts/dev), the same way every time.
#
#   scripts/screenshots.sh [--only NAME,NAME] [--install] [--out DIR]
#
#   --only      just these: taskbar, start-menu, start-menu-light, start-menu-dark, search, settings, settings-windows,
#               settings-search, right-click, right-click-submenu, pin-menu, window-menu, preview
#   --install   copy the results over screenshots/ (default: leave them in --out for a look, and print what each would replace)
#   --out DIR   where the images go (default: a new directory under $TMPDIR or /tmp)
#
# Nothing touches your real desktop: the session has a screen, a shell, a home and a pointer of its own (docs/testing.md), and the
# view window shows what it is doing. The Dock starts from the state the README shows (scripts/tours/common.sh: icons on the left, the
# theme's colours, these Pins) with terminals posing as apps for its windows, so the images do not hold your pins or your windows. The
# wallpaper and colours are the Omarchy theme's, so they change with it: look at every image before committing it.
# Needs scripts/dev (see docs/testing.md), foot, ImageMagick.
#
#   DEV_SIZE=WxH      the session's screen (default 1280x800); the crops are the same on any size, so a bigger screen only adds wallpaper
#
# Every image is the subject plus the same margin ($margin px) of wallpaper on each side, so they look alike side by side. Things
# that sit on the bottom edge (the Dock, and the Preview and Start menu above it) carry on down to the screen's bottom edge, and ones
# against the left edge start at it. The Items, menus and Preview are cropped to the rectangle the shell reports for them (`layout`);
# the settings window to its own size.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HERE=$repo/scripts
DEV=$HERE/dev
export DEV_QUIET=1
only=""
install=false
out=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --only) only=$2; shift 2 ;;
    --install) install=true; shift ;;
    --out) out=$2; shift 2 ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "screenshots: unknown option $1" >&2; exit 2 ;;
  esac
done

for tool in jq magick foot; do
  command -v "$tool" >/dev/null || { echo "screenshots: $tool is not installed" >&2; exit 2; }
done

wanted() { [[ -z $only || ,$only, == *,"$1",* ]]; }

out=${out:-${TMPDIR:-/tmp}/startbar-screenshots-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out"
tmp=$(mktemp -d)
cleanup() { "$DEV" down >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

# The wallpaper left around every subject, in pixels.
margin=32

# shellcheck source=tours/common.sh
source "$HERE/tours/common.sh"
tour_requires || exit 2
STATE_DIR=${XDG_RUNTIME_DIR:-/run/user/$UID}/startbar-dev

"$DEV" down >/dev/null 2>&1 || true
"$DEV" up
# shellcheck disable=SC1091
source "$STATE_DIR/state"
mw=$NW
mh=$NH

# inside COMMAND...: run a function or program in the session's own environment (its home, its guard, its compositor).
inside() { ( eval "$("$DEV" env)"; "$@" ); }

# The Dock as the README shows it, with windows to fill it.
"$DEV" set "$TOUR_PLUGIN_ENTRY" >/dev/null
inside pose org.gnome.Nautilus "Documents" 2a3550 2
inside pose org.gnome.Nautilus "Downloads" 3d3a52 3
inside pose com.mitchellh.ghostty "Terminal" 1f3b2d 4
inside pose btop "btop" 4a2f3a 5
inside settle_focus
readme_state=$TOUR_PLUGIN_ENTRY
sleep 1

shell_layout() { "$DEV" layout 2>/dev/null; }
at() { "$DEV" move "$1" "$2" >/dev/null; }
click() { "$DEV" click "$1" "$2" >/dev/null; }
full() { "$DEV" shot "$1" >/dev/null; }

# wait_for FILTER: run a jq filter (ending in @tsv) over the layout until it gives something, up to 5 s, and print it
# space-separated. Fails if it never does.
wait_for() {
  local out
  for _ in $(seq 1 50); do
    out=$(shell_layout | jq -re "$1 // empty" 2>/dev/null | tr '\t' ' ') || out=""
    if [[ -n $out ]]; then echo "$out"; return 0; fi
    sleep 0.1
  done
  return 1
}

# frame FULL.png OUT.png X Y W H [down]: the rectangle plus $margin on every side, clamped to the screen; with `down`, carried on to
# the screen's bottom edge (for things standing on the Dock).
frame() {
  local x=$(($3 - margin)) y=$(($4 - margin)) w=$(($5 + 2 * margin)) h=$(($6 + 2 * margin))
  ((x < 0)) && { w=$((w + x)); x=0; }
  ((y < 0)) && { h=$((h + y)); y=0; }
  ((x + w > mw)) && w=$((mw - x))
  [[ ${7:-} == down ]] && h=$((mh - y))
  ((y + h > mh)) && h=$((mh - y))
  magick "$1" -crop "${w}x${h}+${x}+${y}" +repage "$2"
}

keep() {
  cp "$1" "$out/$2.png"
  local was=""
  [[ -f $repo/screenshots/$2.png ]] && was=" (now $(magick identify -format '%wx%h' "$repo/screenshots/$2.png"))"
  echo "  $2.png $(magick identify -format '%wx%h' "$out/$2.png")$was"
}

park() { at $((mw - 20)) 200; sleep 0.5; }

if wanted taskbar; then
  park
  full "$tmp/t.png"
  # From the top of the Items (less the margin) down to the bottom edge, 790 wide.
  top=$(shell_layout | jq -r '[.items[].y] | min // 0')
  magick "$tmp/t.png" -crop "790x$((mh - top + margin))+0+$((top - margin))" +repage "$tmp/taskbar.png"
  keep "$tmp/taskbar.png" taskbar
fi

# Start menu in each colour scheme: theme is start-menu.png (and search.png).
start_menu() {
  local scheme=$1 name=$2 typed=${3:-false} box bx by bw bh
  "$DEV" set "{\"colorScheme\":\"$scheme\"}" >/dev/null
  "$DEV" startmenu >/dev/null
  sleep 1
  box=$(wait_for '.menus.start | select(.height > 300) | [.x, .y, .width, .height] | @tsv') || box=""
  read -r bx by bw bh <<<"$box"
  if [[ -z $box ]]; then
    echo "screenshots: the Start menu did not open for $name, skipping it" >&2
  else
    park
    full "$tmp/menu.png"
    frame "$tmp/menu.png" "$tmp/$name.png" "$bx" "$by" "$bw" "$bh" down
    keep "$tmp/$name.png" "$name"
    if $typed && wanted search; then
      "$DEV" type "fi" >/dev/null
      sleep 1
      full "$tmp/typed.png"
      frame "$tmp/typed.png" "$tmp/search.png" "$bx" "$by" "$bw" "$bh" down
      keep "$tmp/search.png" search
    fi
  fi
  "$DEV" close >/dev/null
  sleep 0.6
}
if wanted start-menu || wanted search; then start_menu theme start-menu true; fi
if wanted start-menu-light; then start_menu light start-menu-light; fi
if wanted start-menu-dark; then start_menu dark start-menu-dark; fi
"$DEV" set "$readme_state" >/dev/null

# The settings window's frame is 780x620, centred; its page list is at x+48 and its search box at the top centre (Service.qml,
# settingsWindow).
settings_x=$(((mw - 780) / 2))
settings_y=$(((mh - 620) / 2))
settings_shot() { frame "$tmp/s.png" "$tmp/$1.png" "$settings_x" "$settings_y" 780 620; keep "$tmp/$1.png" "$1"; }
settings_page() { click $((settings_x + 48)) $((settings_y + $1)); sleep 0.6; }

if wanted settings; then
  "$DEV" settings >/dev/null
  settings_page 123   # it opens on the page it was last on: choose the first
  park; full "$tmp/s.png"; settings_shot settings
  "$DEV" close >/dev/null; sleep 0.6
fi

if wanted settings-windows; then
  # With previews off, the options that follow them are dimmed and indented.
  "$DEV" set '{"showPreviews":false}' >/dev/null
  "$DEV" settings >/dev/null
  settings_page 163
  park; full "$tmp/s.png"; settings_shot settings-windows
  "$DEV" close >/dev/null; sleep 0.6
  "$DEV" set "$readme_state" >/dev/null
fi

if wanted settings-search; then
  "$DEV" settings >/dev/null
  # Click into the search box so the keys reach the window, then type.
  click $((mw / 2)) $((settings_y + 30)); sleep 0.3
  "$DEV" type "icon" >/dev/null
  sleep 1
  park; full "$tmp/s.png"; settings_shot settings-search
  "$DEV" close >/dev/null; sleep 0.6
fi

# Where things are comes from the shell itself: `omarchy-shell <id> layout` gives the Dock's Items and any open menu as rectangles in
# pixels from the screen's top-left corner (the panel's `layout()` in Service.qml), so nothing is found by comparing screenshots.

# open_item_menu JQ-TEST: right click the centre of the Item the test picks, and print the rectangle of the menu that opens
# ("x y w h").
open_item_menu() {
  local item x y w h
  item=$(wait_for ".items[] | select($1) | [.x, .y, .width, .height] | @tsv") || return 1
  read -r x y w h <<<"$item"
  "$DEV" rclick $((x + w / 2)) $((y + h / 2)) >/dev/null
  wait_for '.menus.item | select(.height > 40) | [.x, .y, .width, .height] | @tsv'
}

# Bar menu: right click on the bar away from any Item, with auto-hide on as in the image, so the Dock is revealed by the pointer
# first.
if wanted right-click || wanted right-click-submenu; then
  "$DEV" set '{"autoHide":true}' >/dev/null
  at $((mw / 2)) $((mh - 2)); sleep 1.2
  at $((mw * 6 / 10)) $((mh - 12)); sleep 0.5
  "$DEV" rclick $((mw * 6 / 10)) $((mh - 12)) >/dev/null
  if rect=$(wait_for '.menus.bar | select(.height > 100) | [.x, .y, .width, .height] | @tsv'); then
    read -r bx by bw bh <<<"$rect"
    sleep 0.3
    full "$tmp/rc.png"
    frame "$tmp/rc.png" "$tmp/right-click.png" "$bx" "$by" "$bw" "$bh"
    keep "$tmp/right-click.png" right-click
    if wanted right-click-submenu; then
      # Rest on the Start button row, the fourth: three 32 px rows, the 9 px gap before a new group, then half a row, after the
      # menu's 4 px padding.
      at $((bx + bw / 2)) $((by + 4 + 96 + 9 + 16)); sleep 0.3
      at $((bx + bw / 2 + 3)) $((by + 4 + 96 + 9 + 16)); sleep 0.8
      if sub=$(wait_for '.menus.barSub | [.x, .y, .width, .height] | @tsv'); then
        read -r sx sy sw sh <<<"$sub"
        full "$tmp/rcs.png"
        ux=$((bx < sx ? bx : sx)); uy=$((by < sy ? by : sy))
        ur=$((bx + bw > sx + sw ? bx + bw : sx + sw)); ub=$((by + bh > sy + sh ? by + bh : sy + sh))
        frame "$tmp/rcs.png" "$tmp/right-click-submenu.png" "$ux" "$uy" $((ur - ux)) $((ub - uy))
        keep "$tmp/right-click-submenu.png" right-click-submenu
      else
        echo "screenshots: the submenu did not open, skipping it" >&2
      fi
    fi
  else
    echo "screenshots: the Bar menu did not open, skipping it" >&2
  fi
  click $((mw / 2)) 200
  sleep 0.5
  "$DEV" set "$readme_state" >/dev/null
fi

# pin-menu: the first Pin with no Windows (the App's actions, its icon and name, Unpin from taskbar).
if wanted pin-menu; then
  park
  if rect=$(open_item_menu '.kind == "pin"'); then
    read -r bx by bw bh <<<"$rect"
    sleep 0.3
    full "$tmp/pm.png"
    frame "$tmp/pm.png" "$tmp/pin-menu.png" "$bx" "$by" "$bw" "$bh"
    keep "$tmp/pin-menu.png" pin-menu
  else
    echo "screenshots: found no Pin without Windows, skipping pin-menu" >&2
  fi
  click $((mw / 2)) 200; sleep 0.5
fi

# window-menu: a terminal posing as btop, whose Item is not pinned (the App's actions, the window's state, Close Window, then the
# App's icon and name and Pin to taskbar).
if wanted window-menu; then
  park
  if rect=$(open_item_menu '.appId == "btop"'); then
    read -r bx by bw bh <<<"$rect"
    sleep 0.3
    full "$tmp/wm.png"
    frame "$tmp/wm.png" "$tmp/window-menu.png" "$bx" "$by" "$bw" "$bh"
    keep "$tmp/window-menu.png" window-menu
  else
    echo "screenshots: the window's menu did not open, skipping window-menu" >&2
  fi
  click $((mw / 2)) 200; sleep 0.5
fi

# Preview: two windows of one app make a group Item, whose Preview is wider than any single Window's. Hover that Item and crop to the
# Preview and the Dock under it.
if wanted preview; then
  park
  if item=$(wait_for '.items[] | select(.appId == "org.gnome.Nautilus") | [.x, .y, .width, .height] | @tsv'); then
    read -r x y w h <<<"$item"
    # From the Dock's edge first: jumping straight onto an Item can lose the hover.
    at $((mw / 2)) $((mh - 2)); sleep 0.5
    at $((x + w / 2)) $((y + h / 2))
    if rect=$(wait_for '.menus.preview | select(.width > 100 and .height > 50) | [.x, .y, .width, .height] | @tsv'); then
      # The Preview slides up as it opens: read its place again once it has settled.
      sleep 0.8
      rect=$(wait_for '.menus.preview | select(.width > 100 and .height > 50) | [.x, .y, .width, .height] | @tsv') || true
      read -r bx by bw bh <<<"$rect"
      full "$tmp/pv.png"
      frame "$tmp/pv.png" "$tmp/preview.png" "$bx" "$by" "$bw" "$bh" down
      keep "$tmp/preview.png" preview
    else
      echo "screenshots: the Preview did not open, skipping it" >&2
    fi
  else
    echo "screenshots: could not find a group Item of the two windows, skipping the Preview" >&2
  fi
  park
fi

if $install; then
  echo "screenshots: installing into screenshots/"
  find "$out" -maxdepth 1 -name '*.png' -exec cp -t "$repo/screenshots" {} +
  git -C "$repo" status --short screenshots
else
  echo "screenshots: look at them in $out; --install copies them over screenshots/"
fi
