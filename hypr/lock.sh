#!/bin/bash
# hyprpaper >= 0.8 dropped the "listloaded" IPC request; "listactive" prints "MONITOR: /path"
WALLPAPER=$(hyprctl hyprpaper listactive 2>/dev/null | head -1 | sed 's/^[^:]*: *//')
[ -f "$WALLPAPER" ] || WALLPAPER="$HOME/Pictures/Wallpapers/wallpaper.jpg"
if [ -f "$WALLPAPER" ]; then
    cp -f "$WALLPAPER" /tmp/hyprlock-wallpaper
fi
exec hyprlock
