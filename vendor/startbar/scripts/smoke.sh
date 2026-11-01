#!/usr/bin/env bash
# Smoke test: start the nested test session (scripts/dev) with this checkout loaded, fail on any error the plugin logs, and screenshot the
# Dock, the Start menu and the settings window in each colour scheme. Look at the screenshots afterwards: the script only knows that the
# shell loaded the plugin without complaint, not that what it drew is right.
#
#   scripts/smoke.sh [--out DIR] [--type] [--position EDGE]
#
#   --out DIR       where the screenshots go (default: a new directory under $TMPDIR or /tmp)
#   --type          also type into the Start menu's search box and capture the results
#   --position EDGE run with the Dock on this edge: bottom (default), top, left or right
#
# Everything happens in the session, a second desktop that your mouse and keyboard cannot reach, with a home of its own: your real shell
# is not restarted, your shell.json is not edited, and your windows are not touched. DEV_WATCH=0 hides the window that shows the
# session on your screen. The session is ended when the script ends, however it ends.
#
# It cannot hover or drag: for a Preview, the Item menu or the Bar menu, drive the session by hand (scripts/dev move, click, rclick;
# docs/testing.md), or run a tour (scripts/tour.sh). Drag, and anything it could not reach, still needs the checklist in CONTRIBUTING.md.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dev=$repo/scripts/dev
out=""
type_search=false
position=bottom

while [[ $# -gt 0 ]]; do
  case $1 in
    --out) out=$2; shift 2 ;;
    --type) type_search=true; shift ;;
    --position) position=$2; shift 2 ;;
    -h | --help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "smoke: unknown option $1" >&2; exit 2 ;;
  esac
done
case $position in bottom | top | left | right) ;; *) echo "smoke: --position is bottom, top, left or right" >&2; exit 2 ;; esac

out=${out:-${TMPDIR:-/tmp}/startbar-smoke-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out"
trap '"$dev" down >/dev/null 2>&1 || true' EXIT

"$dev" down >/dev/null 2>&1 || true
"$dev" up
# One window, so that the Dock shows an Item as well as the Start button.
"$dev" run foot -a foot sleep 600 >/dev/null

shot() {
  "$dev" shot "$out/$1.png" >/dev/null
  echo "  $out/$1.png"
}

echo "smoke: capturing"
for scheme in theme light dark; do
  "$dev" set "{\"colorScheme\": \"$scheme\", \"startCommand\": \"builtin\", \"autoHide\": false, \"showStart\": true, \"showClock\": true, \"position\": \"$position\"}" >/dev/null
  shot "$scheme-1-dock"
  "$dev" startmenu >/dev/null
  shot "$scheme-2-start-menu"
  if $type_search; then
    "$dev" type "fi" >/dev/null
    sleep 1
    shot "$scheme-3-search"
  fi
  "$dev" close >/dev/null
  sleep 0.6
done

"$dev" settings >/dev/null
shot "settings-window"
"$dev" close >/dev/null

if ! errors=$("$dev" errors 2>&1); then
  echo "smoke: FAILED, the plugin logged:" >&2
  echo "$errors" >&2
  exit 1
fi
echo "smoke: ok, nothing logged by the plugin. Now look at the screenshots in $out"
