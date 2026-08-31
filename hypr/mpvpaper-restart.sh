#!/bin/sh


WATCH="$HOME/.config/hypr/mpvpaper-watch.sh"

if pgrep -f "[m]pvpaper-watch.sh" >/dev/null; then
    pkill -9 -x mpvpaper
else
    setsid -f "$WATCH" >/dev/null 2>&1
fi
