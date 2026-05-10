#!/bin/bash
WALLPAPER=$(awww query 2>/dev/null | head -1 | grep -oP 'image: \K.*')
if [ -n "$WALLPAPER" ]; then
    cp -f "$WALLPAPER" /tmp/hyprlock-wallpaper
fi
exec hyprlock
