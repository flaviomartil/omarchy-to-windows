#!/usr/bin/env bash
# Drive the real pointer, to try what `npm run smoke` cannot: hover a Dock Item,
# move onto its Preview, right-click. Needs ydotool and a writable /dev/uinput
# (docs/hyprland-notes.md "Moving the pointer").
#   scripts/pointer.sh move X Y     move there with real motion (a hover fires)
#   scripts/pointer.sh reveal       warp to the bottom edge of the monitor under the
#                                   pointer and wait, so an auto-hidden Dock rises
#   scripts/pointer.sh left|right   click, and say which windows are under the pointer
#   scripts/pointer.sh key CODE:1 CODE:0 ...   keys, only while a throwaway window
#                                   (class startbar-screenshot or spare-test) has focus
#   scripts/pointer.sh shot FILE [WxH+X+Y]
#                                   screenshot the monitor under the pointer, cropped
#                                   to WxH+X+Y of that monitor if given
#
# X and Y are global layout coordinates (a second monitor starts at its x/y offset).
# A click goes to whatever is under the pointer, and an auto-hidden Dock is not
# there until `reveal`: shoot and look before the first click.
# A Preview needs the pointer to rest on its Item for ~400 ms, then to move onto
# the thumbnail: sleep between the calls and shoot to see what is up.
set -euo pipefail

export YDOTOOL_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/.ydotool_socket"
if [ ! -S "$YDOTOOL_SOCKET" ]; then
  nohup ydotoold --socket-path="$YDOTOOL_SOCKET" --socket-own="$(id -u):$(id -g)" >/dev/null 2>&1 &
  sleep 1
fi

case "${1:-}" in
  move)
    # cursor.move puts the pointer there but raises no hover; a 1 px nudge does.
    hyprctl dispatch "hl.dsp.cursor.move({ x = $2, y = $3 })" >/dev/null
    ydotool mousemove -x 1 -y 0
    ydotool mousemove -x -1 -y 0
    ;;
  reveal)
    read -r mx my mh < <(hyprctl -j monitors | jq -r --argjson c "$(hyprctl -j cursorpos)" \
      '.[] | select($c.x >= .x and $c.x < .x + .width and $c.y >= .y and $c.y < .y + .height) | "\($c.x) \(.y) \(.height)"')
    "$0" move "$mx" $((my + mh - 1))
    sleep 1
    ;;
  left|right)
    under=$(hyprctl -j clients | jq -r --argjson c "$(hyprctl -j cursorpos)" \
      '[.[] | select(.mapped and $c.x >= .at[0] and $c.x < .at[0] + .size[0] and $c.y >= .at[1] and $c.y < .at[1] + .size[1]) | .class] | join(", ")')
    echo "pointer: $1 click over windows: ${under:-none}" >&2
    if [ "$1" = left ]; then ydotool click 0xC0 >/dev/null; else ydotool click 0xC1 >/dev/null; fi
    ;;
  key)
    shift
    focused=$(hyprctl -j activewindow | jq -r '.class // ""')
    case $focused in
      startbar-screenshot|spare-test) ydotool key "$@" ;;
      *) echo "pointer: refusing to send keys to '$focused': focus a throwaway window first" >&2; exit 1 ;;
    esac
    ;;
  shot)
    mon=$(hyprctl -j monitors | jq -r --argjson c "$(hyprctl -j cursorpos)" \
      '.[] | select($c.x >= .x and $c.x < .x + .width and $c.y >= .y and $c.y < .y + .height) | .name')
    grim -o "$mon" "$2"
    if [ -n "${3:-}" ]; then magick "$2" -crop "$3" +repage "$2"; fi
    ;;
  *) echo "usage: $0 move X Y | reveal | left | right | key CODE:1 CODE:0 ... | shot FILE [WxH+X+Y]" >&2; exit 2 ;;
esac
