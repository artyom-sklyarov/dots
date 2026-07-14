#!/bin/sh

# Hang detector for the mpvpaper wallpaper. Companion to mpvpaper-watch.sh
# and mpvpaper-pauser.sh.
#
# A "hang" here is mpv still alive but its playback clock frozen while it is
# meant to be playing -- or the IPC socket gone unresponsive. Neither shows
# up as a process exit, so mpvpaper-watch.sh (which only reacts to exits)
# never notices. This polls over IPC and, on a confirmed hang, SIGKILLs
# mpvpaper so the watcher respawns it. Every action is timestamped to a log.
#
# Wire it in hyprland.conf alongside the others:
#   exec-once = ~/.config/hypr/mpvpaper-health.sh
#
# Watch it live:  tail -f ~/.local/state/mpvpaper-health.log

SOCK="${XDG_RUNTIME_DIR:-/tmp}/mpvpaper.sock"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/mpvpaper-health.log"
INTERVAL=15        # seconds between health checks
COOLDOWN=20        # seconds to let a fresh mpvpaper stabilise after a restart

mkdir -p "$(dirname "$LOG")"

# Single instance only (matches the pauser's guard).
[ "$(pgrep -cf "[m]pvpaper-health.sh")" -gt 1 ] && exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

# Query one mpv property over IPC. Empty output = no reply within the socat
# timeout (mpv wedged, or socket gone).
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

    # Not running at all is the watcher's problem, not a hang.
    pgrep -x mpvpaper >/dev/null || continue

    pause=$(mpv_get pause)
    if [ -z "$pause" ]; then
        restart "IPC unresponsive"
        continue
    fi

    # Paused on purpose by the pauser (workspace covered) -> healthy.
    [ "$pause" = true ] && continue

    # Unpaused: the playback clock must advance between two samples.
    t1=$(mpv_get time-pos)
    sleep 1
    t2=$(mpv_get time-pos)

    if [ -n "$t1" ] && [ "$t1" = "$t2" ]; then
        # Re-check pause in case the pauser paused it between samples
        # (would look frozen but is fine).
        [ "$(mpv_get pause)" = true ] && continue
        restart "playback frozen at time-pos=$t1"
    fi
done
