#!/usr/bin/env bash
# Record Hyprland's window, focus and workspace events with timestamps, to see
# who changed focus and in what order while you reproduce something by hand.
#   scripts/hypr-events.sh start [file]   record in the background (default $XDG_RUNTIME_DIR/startbar-events.log)
#   scripts/hypr-events.sh stop           stop it
# It stops by PID, not `pkill -f`: that pattern also matches the shell running it.
set -euo pipefail
umask 077

runtime="${XDG_RUNTIME_DIR:?not running under Hyprland}"
if [[ $runtime != /* || ! -d $runtime || ! -O $runtime || $(stat -c %a -- "$runtime") != 700 ]]; then
  echo "event logging requires a private runtime directory owned by the current user" >&2
  exit 1
fi
pidfile="$runtime/startbar-events.pid"
socket="$runtime/hypr/${HYPRLAND_INSTANCE_SIGNATURE:?not running under Hyprland}/.socket2.sock"

case "${1:-}" in
  start)
    log="${2:-$runtime/startbar-events.log}"
    : > "$log"
    chmod 600 -- "$log"
    nohup bash -c '
      socat -u "UNIX-CONNECT:$1" - |
        grep --line-buffered -E "^(activewindowv2|openwindow|closewindow|workspacev2|focusedmonv2)" |
        while IFS= read -r line; do printf "%s %s\n" "$(date +%T.%3N)" "$line"; done >> "$2"
    ' bash "$socket" "$log" >/dev/null 2>&1 &
    echo $! > "$pidfile"
    echo "recording to $log"
    ;;
  stop)
    [ -f "$pidfile" ] || { echo "not recording"; exit 0; }
    pkill -P "$(cat "$pidfile")" || true
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
    ;;
  *)
    echo "usage: $0 start [file] | stop" >&2
    exit 2
    ;;
esac
