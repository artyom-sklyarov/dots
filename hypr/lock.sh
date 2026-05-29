#!/bin/bash
WALLPAPER=$(hyprctl hyprpaper listloaded 2>/dev/null | head -1)
if [ -n "$WALLPAPER" ]; then
    cp -f "$WALLPAPER" /tmp/hyprlock-wallpaper
fi
exec hyprlock
