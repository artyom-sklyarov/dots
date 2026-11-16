#!/bin/sh

(
    sleep 3
    hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
    sleep 2
    hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
) &

(
    rfkill block bluetooth
    sleep 2
    rfkill unblock bluetooth
    sleep 3
    BT_DEVICE=$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bt-device" 2>/dev/null)
    [ -n "$BT_DEVICE" ] || exit 0
    for i in 1 2 3; do
        timeout 5 bluetoothctl connect "$BT_DEVICE" 2>&1 | grep -q "Connection successful" && break
        sleep 2
    done
) &

if pgrep -x wlsunset >/dev/null 2>&1; then
    killall wlsunset
    wlsunset -t 4000 -T 6500 &
fi

eww reload
