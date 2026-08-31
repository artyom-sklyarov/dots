#!/bin/bash

set -u
MONITOR="eDP-1"
STATE=/tmp/lid-disabled-edp1

other_active_count() {
    hyprctl -j monitors 2>/dev/null \
        | jq --arg m "$MONITOR" '[.[] | select(.name != $m)] | length'
}

case "${1:-}" in
    close)
        if [ "$(other_active_count)" -ge 1 ]; then
            hyprctl keyword monitor "$MONITOR, disable" && touch "$STATE"
        fi
        ;;
    open)
        if [ -f "$STATE" ]; then
            hyprctl reload
            rm -f "$STATE"
        fi
        ;;
    *)
        echo "usage: $0 close|open" >&2
        exit 2
        ;;
esac
