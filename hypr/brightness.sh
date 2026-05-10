#!/bin/sh

action="$1"
value="${2:-5}"
min_pct=1

for dev in /sys/class/backlight/*/; do
    dev_name=$(basename "$dev")
    case "$action" in
        up)   brightnessctl -d "$dev_name" set "${value}%+" ;;
        down) max=$(brightnessctl -d "$dev_name" max)
              min_val=$(( max * min_pct / 100 ))
              [ "$min_val" -lt 1 ] && min_val=1
              brightnessctl -d "$dev_name" set "${value}%-" -n "$min_val" ;;
        set)  brightnessctl -d "$dev_name" set "${value}%" ;;
    esac
done

for display in $(ddcutil detect --brief 2>/dev/null | grep -oP 'Display \K\d+'); do
    cur=$(ddcutil --display "$display" getvcp 10 --brief 2>/dev/null | awk '{print $4}')
    [ -z "$cur" ] && continue
    case "$action" in
        up)   new=$(( cur + value )); [ "$new" -gt 100 ] && new=100 ;;
        down) new=$(( cur - value )); [ "$new" -lt "$min_pct" ] && new=$min_pct ;;
        set)  new=$value; [ "$new" -lt "$min_pct" ] && new=$min_pct; [ "$new" -gt 100 ] && new=100 ;;
    esac
    ddcutil --display "$display" setvcp 10 "$new" --noverify &
done
wait
