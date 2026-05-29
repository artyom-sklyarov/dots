#!/bin/sh
# Restart services whose connections break after sleep.
# Runs fully in background so resume is instant.

(
    # Hard-reset BT radio (rfkill clears stale HCI state that power off/on doesn't)
    rfkill block bluetooth
    sleep 2
    rfkill unblock bluetooth
    sleep 3
    # Retry connection in case of race with autoconnect (timeout each attempt)
    for i in 1 2 3; do
        timeout 5 bluetoothctl connect 80:99:E7:FF:B6:17 2>&1 | grep -q "Connection successful" && break
        sleep 2
    done
) &

# Restart wlsunset if it was running (gamma control goes stale)
if pgrep -x wlsunset >/dev/null 2>&1; then
    killall wlsunset
    wlsunset -t 4000 -T 6500 &
fi

# Reload eww. Its deflisten window-title pipe can deadlock across lock/wake:
# if eww's reader is starved during the transient (hyprlock foreground, surface
# rebuild on DPMS-on), the pipe fills (~64 KiB), printf blocks forever, and
# eww does NOT auto-respawn the dead script. `eww reload` restarts all
# listeners with fresh pipes — cheap, and keeps the bar visible.
eww reload
