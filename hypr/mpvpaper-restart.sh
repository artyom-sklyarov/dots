#!/bin/sh

# Manual restart for the mpvpaper wallpaper.
#
# mpvpaper-watch.sh respawns mpvpaper on any *non-zero* exit and stops on a
# clean exit (code 0). So a restart is just SIGKILL: the watcher brings it
# back within ~1s with the same args. If the watcher isn't running (e.g.
# it hit its crash-loop bailout), start it -- it launches mpvpaper itself.
#
# Bind it in hyprland.conf, e.g.:
#   bind = $mainMod SHIFT, W, exec, ~/.config/hypr/mpvpaper-restart.sh

WATCH="$HOME/.config/hypr/mpvpaper-watch.sh"

if pgrep -f "[m]pvpaper-watch.sh" >/dev/null; then
    # Watcher alive: SIGKILL -> non-zero exit -> automatic respawn.
    pkill -9 -x mpvpaper
else
    # No watcher: start it detached; it spawns mpvpaper on its own.
    setsid -f "$WATCH" >/dev/null 2>&1
fi
