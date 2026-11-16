#!/bin/sh

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

emit() {
    ws=$(hyprctl workspaces -j) || return 1
    mon=$(hyprctl monitors -j) || return 1
    jq -cn --argjson ws "$ws" --argjson mon "$mon" '
        ($ws | map({key: .name, value: .}) | from_entries) as $w
        | $mon
        | map((.specialWorkspace.name // "") as $sp
              | (if $sp != "" then $sp else .activeWorkspace.name end) as $n
              | {(.name): ($w[$n] | if . == null or .windows == 0 then "" else .lastwindowtitle end)})
        | add // {}'
}

last=
{ echo init; exec socat -u "UNIX-CONNECT:$SOCK" - 2>/dev/null; } | while IFS= read -r ev; do
    case $ev in activelayout*|urgent*|bell*) continue ;; esac
    out=$(emit) || continue
    [ "$out" = "$last" ] && continue
    printf '%s\n' "$out"
    last=$out
done
