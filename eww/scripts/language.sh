#!/usr/bin/env bash

KB="at-translated-set-2-keyboard"

emit() {
    layout=$(hyprctl devices -j 2>/dev/null | jq -r --arg kb "$KB" \
        '.keyboards[] | select(.name == $kb) | .active_keymap')
    case "$layout" in
        *English*) echo "EN" ;;
        *Russian*) echo "RU" ;;
        *) echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]' ;;
    esac
}

emit
SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
if [ -S "$SOCK" ]; then
    socat -u UNIX-CONNECT:"$SOCK" - | while read -r line; do
        case "$line" in
            activelayout*) emit ;;
        esac
    done
fi
