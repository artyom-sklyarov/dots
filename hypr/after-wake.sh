#!/bin/sh

(
    rfkill block bluetooth
    sleep 2
    rfkill unblock bluetooth
    sleep 3
    for i in 1 2 3; do
        timeout 5 bluetoothctl connect 80:99:E7:FF:B6:17 2>&1 | grep -q "Connection successful" && break
        sleep 2
    done
) &

if pgrep -x wlsunset >/dev/null 2>&1; then
    killall wlsunset
    wlsunset -t 4000 -T 6500 &
fi

eww reload
