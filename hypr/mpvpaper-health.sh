#!/bin/sh


SOCK="${XDG_RUNTIME_DIR:-/tmp}/mpvpaper.sock"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mpvpaper-health.log"
INTERVAL=15
COOLDOWN=20

mkdir -p "$(dirname "$LOG")"

[ "$(pgrep -cf "[m]pvpaper-health.sh")" -gt 1 ] && exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

mpv_get() {
    printf '{"command":["get_property","%s"]}\n' "$1" \
        | socat -T2 - "$SOCK" 2>/dev/null \
        | jq -r 'select(.error=="success") | .data' 2>/dev/null | head -1
}

restart() {
    log "restarting: $1"
    pkill -9 -x mpvpaper
    sleep "$COOLDOWN"
}

log "health monitor started (interval=${INTERVAL}s)"

while :; do
    sleep "$INTERVAL"

    pgrep -x mpvpaper >/dev/null || continue

    pause=$(mpv_get pause)
    if [ -z "$pause" ]; then
        restart "IPC unresponsive"
        continue
    fi

    [ "$pause" = true ] && continue

    t1=$(mpv_get time-pos)
    sleep 1
    t2=$(mpv_get time-pos)

    if [ -n "$t1" ] && [ "$t1" = "$t2" ]; then
        [ "$(mpv_get pause)" = true ] && continue
        restart "playback frozen at time-pos=$t1"
    fi
done
