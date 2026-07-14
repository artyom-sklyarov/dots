#!/bin/sh

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/eww"

eww_cmd() {
    eww -c "$CONFIG_DIR" "$@"
}

monitors=$(
    hyprctl monitors -j 2>/dev/null \
        | jq -r '.[].name' 2>/dev/null
)

active_bar_ids=$(
    eww_cmd active-windows 2>/dev/null \
        | awk -F': ' '$2 == "bar" && $1 ~ /^bar($|-)/ { print $1 }'
)

for id in $active_bar_ids; do
    eww_cmd close "$id" >/dev/null 2>&1 || true
done

if [ -z "$monitors" ]; then
    eww_cmd open --id bar-0 --screen 0 --arg monitor=0 bar
    exit
fi

for monitor in $monitors; do
    id=$(printf '%s' "$monitor" | tr -c 'A-Za-z0-9_.-' '_')
    eww_cmd open --id "bar-$id" --screen "$monitor" --arg "monitor=$monitor" bar
done
