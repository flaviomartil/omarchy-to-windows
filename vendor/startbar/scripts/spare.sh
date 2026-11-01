#!/usr/bin/env bash
# A spare window to try Hyprland calls and window logic on, so a test never
# touches the user's own windows (docs/hyprland-notes.md).
#
#   scripts/spare.sh open          start a spare foot window; print its address
#   scripts/spare.sh state ADDR    print "ws=3 fs=1 floating=false" for it
#   scripts/spare.sh close ADDR    close it and go back to the workspace `open` was run on
#
# The window opens wherever the user is looking, and floats on an Omarchy
# floating workspace. A live StartBar hook acts on it like any new window.
set -euo pipefail

saved=${XDG_RUNTIME_DIR:-/tmp}/startbar-spare-workspace
class=spare-test

address() {
  hyprctl -j clients | jq -r --arg c "$class" 'first(.[] | select(.class == $c) | .address) // empty'
}

case ${1:-} in
  open)
    [[ -z $(address) ]] || { echo "spare: one is already open" >&2; exit 1; }
    hyprctl -j monitors | jq -r 'first(.[] | select(.focused) | .activeWorkspace.id)' >"$saved"
    foot -a "$class" sleep 600 >/dev/null 2>&1 &
    for _ in $(seq 30); do
      sleep 0.1
      [[ -z $(address) ]] || break
    done
    address | grep . || { echo "spare: the window did not open" >&2; exit 1; }
    ;;
  state)
    [[ ${2:-} =~ ^0x[0-9a-f]+$ ]] || { echo "usage: spare.sh state ADDR" >&2; exit 2; }
    hyprctl -j clients | jq -r --arg a "$2" '.[] | select(.address == $a) | "ws=\(.workspace.id) fs=\(.fullscreen) floating=\(.floating)"'
    ;;
  close)
    [[ ${2:-} =~ ^0x[0-9a-f]+$ ]] || { echo "usage: spare.sh close ADDR" >&2; exit 2; }
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$2\" })" >/dev/null
    sleep 0.7
    if [[ -f $saved ]]; then
      hyprctl dispatch "hl.dsp.focus({ workspace = \"$(cat "$saved")\" })" >/dev/null
      rm -f "$saved"
    fi
    ;;
  *)
    echo "usage: spare.sh open | state ADDR | close ADDR" >&2
    exit 2
    ;;
esac
