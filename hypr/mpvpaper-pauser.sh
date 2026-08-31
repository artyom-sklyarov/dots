#!/bin/sh


SOCK="${XDG_RUNTIME_DIR:-/tmp}/mpvpaper.sock"
SIG="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -1t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)}"
EVENTS="$XDG_RUNTIME_DIR/hypr/$SIG/.socket2.sock"

[ "$(pgrep -cf "[m]pvpaper-pauser.sh")" -gt 1 ] && exit 0

set_pause() {
    printf '{"command":["set_property","pause",%s]}\n' "$1" \
        | socat - "$SOCK" >/dev/null 2>&1
}

sync_state() {
    visible=$(hyprctl monitors -j | jq -c '[.[].activeWorkspace.id]') || return
    covered=$(hyprctl workspaces -j | jq --argjson v "$visible" \
        '[.[] | select(.id as $i | $v | index($i)) | .hasfullscreen]
         | (length > 0) and all')
    if [ "$covered" = true ]; then
        set_pause true
    else
        set_pause false
    fi
}

while :; do
    sync_state
    socat -u UNIX-CONNECT:"$EVENTS" - 2>/dev/null | while IFS= read -r ev; do
        case "$ev" in
            fullscreen'>>'* | workspace'>>'* | focusedmon'>>'* | \
            openwindow'>>'* | closewindow'>>'* | movewindowv2'>>'* | \
            monitoradded'>>'* | monitorremoved'>>'*)
                sync_state ;;
        esac
    done
    sleep 2
done
