#!/bin/sh
BAT="/sys/class/power_supply/BAT1"
[ -d "$BAT" ] || BAT="/sys/class/power_supply/BAT0"
[ -d "$BAT" ] || { echo ""; exit 0; }

pct=$(cat "$BAT/capacity" 2>/dev/null)
status=$(cat "$BAT/status" 2>/dev/null)

case "$status" in
    Charging)    icon="󰂄" ;;
    Full)        icon="󰚥" ;;
    *)           icon="󰁹" ;;
esac

echo "$icon ${pct}%"
