#!/bin/sh
# Emits name of currently visible special workspace (without "special:" prefix),
# or "" when none. Driven by Hyprland's IPC event stream so eww updates instantly.

emit_current() {
    hyprctl monitors -j 2>/dev/null \
        | jq -r 'map(.specialWorkspace.name) | map(select(. != "")) | first // "" | sub("^special:"; "")'
}

emit_current

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
exec socat -u "UNIX-CONNECT:$SOCK" - 2>/dev/null \
    | stdbuf -oL awk -F'>>' '
        /^activespecial>>/ {
            name = $2
            sub(/,.*/, "", name)
            sub(/^special:/, "", name)
            print name
            fflush()
        }'
