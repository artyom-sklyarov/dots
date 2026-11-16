#!/bin/sh

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

emit() {
    ws=$(hyprctl workspaces -j) || return 1
    mon=$(hyprctl monitors -j) || return 1
    jq -cn --argjson ws "$ws" --argjson mon "$mon" '
        [$mon[].activeWorkspace.id] as $vis
        | $ws | map(.id //= -99) | sort_by(.id)   # 0.57 dropped "id" on special workspaces
        | map({id, name, monitor, windows,
               active: (.id as $i | any($vis[]; . == $i))})'
}

last=
{ echo init; exec socat -u "UNIX-CONNECT:$SOCK" - 2>/dev/null; } | while IFS= read -r ev; do
    case $ev in windowtitle*|activelayout*|activewindow*|urgent*|bell*|minimized*) continue ;; esac
    out=$(emit) || continue
    [ "$out" = "$last" ] && continue
    printf '%s\n' "$out"
    last=$out
done
