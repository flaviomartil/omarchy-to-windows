#!/usr/bin/env bash
# Try StartBar settings on the live shell, then put your config back. Merges the
# JSON object into StartBar's entry in ~/.config/omarchy/shell.json, waits for the
# shell to re-read it, runs the command (default: print the Dock layout as one
# line of JSON), and restores shell.json on exit, even when the command fails.
#   scripts/try-setting.sh '{"position":"top","autoHide":false}'
#   scripts/try-setting.sh '{"position":"left"}' -- scripts/pointer.sh shot /tmp/left.png 300x600+0+0
# The file is rewritten in place (cat >, not mv): the shell watches it.
set -euo pipefail

config="$HOME/.config/omarchy/shell.json"
id="io.github.bmaltais.startbar"
patch="${1:?usage: try-setting.sh '<json object>' [-- command args...]}"
shift
[ "${1:-}" = "--" ] && shift

jq -e --arg id "$id" '.plugins | any(.id == $id)' "$config" >/dev/null \
  || { echo "try-setting: $id is not in $config" >&2; exit 1; }
jq -e 'type == "object"' <<<"$patch" >/dev/null \
  || { echo "try-setting: the setting must be a JSON object" >&2; exit 2; }

backup="$(mktemp)"
cp "$config" "$backup"
restore() {
  cat "$backup" >"$config"
  rm -f "$backup"
  sleep 1.5
}
trap restore EXIT

jq --arg id "$id" --argjson patch "$patch" \
  '(.plugins[] | select(.id == $id)) += $patch' "$backup" >"$config"
sleep 1.5

if [ "$#" -gt 0 ]; then
  "$@"
else
  omarchy-shell "$id" layout | jq -c .
fi
