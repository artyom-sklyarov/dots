#!/bin/bash
WALLPAPER=$(hyprctl hyprpaper listactive 2>/dev/null | head -1 | sed 's/^[^:]*: *//')
[ -f "$WALLPAPER" ] || WALLPAPER="$HOME/Pictures/Wallpapers/wallpaper.jpg"
if [ -f "$WALLPAPER" ]; then
    cp -f "$WALLPAPER" /tmp/hyprlock-wallpaper
fi
exec hyprlock
