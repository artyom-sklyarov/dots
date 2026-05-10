#!/bin/sh

mon_count=$(hyprctl monitors -j 2>/dev/null | jq 'length' 2>/dev/null)
if [ -n "$mon_count" ] && [ "$mon_count" -gt 1 ]; then
    echo ""
    exit 0
fi

dev=""
for candidate in intel_backlight amdgpu_bl0 amdgpu_bl1 nvidia_0; do
    [ -d "/sys/class/backlight/$candidate" ] && dev="$candidate" && break
done
[ -z "$dev" ] && dev=$(ls -1 /sys/class/backlight/ 2>/dev/null | head -n1)

if [ -n "$dev" ]; then
    pct=$(brightnessctl -d "$dev" info -m 2>/dev/null | cut -d, -f4 | tr -d '%')
    [ -n "$pct" ] && echo "$pct" || echo "--"
else
    echo "--"
fi
