#!/bin/sh
# Emit the current backlight % for the laptop panel, OR empty string when
# multiple Hyprland monitors are active (per-monitor brightness can't be
# meaningfully shown by one widget). The eww widget hides the % suffix when
# this script returns empty.
#
# Picks intel_backlight first (canonical Intel iGPU backlight controller on
# hybrid laptops where nvidia_0 is a redundant interface), then amdgpu_bl*,
# then nvidia_0, then any /sys/class/backlight/*.

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
