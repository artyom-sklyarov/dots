#!/bin/sh
muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -o "MUTED" || true)
vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2 * 100)}')
if [ -n "$muted" ]; then
    echo "󰖁"
else
    echo "󰕾 ${vol}%"
fi
