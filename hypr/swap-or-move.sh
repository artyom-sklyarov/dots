#!/bin/bash
DIR="$1"
ACTIVE=$(hyprctl activewindow -j)
ADDR=$(echo "$ACTIVE" | jq -r '.address')
FLOATING=$(echo "$ACTIVE" | jq -r '.floating')
WORKSPACE=$(echo "$ACTIVE" | jq -r '.workspace.id')
MON_ID=$(echo "$ACTIVE" | jq -r '.monitor')
TILED=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $WORKSPACE and .floating == false)] | length")

MON=$(hyprctl monitors -j | jq ".[] | select(.id == $MON_ID)")
MON_X=$(echo "$MON" | jq -r '.x')
MON_Y=$(echo "$MON" | jq -r '.y')
MON_W=$(echo "$MON" | jq -r '.width')
MON_H=$(echo "$MON" | jq -r '.height')
SCALE=$(echo "$MON" | jq -r '.scale')
RES_TOP=$(echo "$MON" | jq -r '.reserved[1]')

MW=$(awk "BEGIN {printf \"%d\", $MON_W / $SCALE}")
MH=$(awk "BEGIN {printf \"%d\", $MON_H / $SCALE - $RES_TOP}")
MY=$((MON_Y + RES_TOP))
HALF_W=$((MW / 2))
HALF_H=$((MH / 2))

if [ "$TILED" -ge 2 ] && [ "$FLOATING" = "false" ]; then
    hyprctl dispatch swapwindow "$DIR"
else
    [ "$FLOATING" = "false" ] && hyprctl dispatch setfloating "address:$ADDR"
    case "$DIR" in
        l) hyprctl dispatch movewindowpixel "exact ${MON_X} ${MY},address:$ADDR"
           hyprctl dispatch resizewindowpixel "exact ${HALF_W} ${MH},address:$ADDR" ;;
        r) hyprctl dispatch movewindowpixel "exact $((MON_X + HALF_W)) ${MY},address:$ADDR"
           hyprctl dispatch resizewindowpixel "exact ${HALF_W} ${MH},address:$ADDR" ;;
        u) hyprctl dispatch movewindowpixel "exact ${MON_X} ${MY},address:$ADDR"
           hyprctl dispatch resizewindowpixel "exact ${MW} ${HALF_H},address:$ADDR" ;;
        d) hyprctl dispatch movewindowpixel "exact ${MON_X} $((MY + HALF_H)),address:$ADDR"
           hyprctl dispatch resizewindowpixel "exact ${MW} ${HALF_H},address:$ADDR" ;;
    esac
fi
