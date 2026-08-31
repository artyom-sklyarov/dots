#!/usr/bin/env bash

KB="${KB:-at-translated-set-2-keyboard}"
INTERVAL="${LANGUAGE_POLL_INTERVAL:-1}"

declare -A layouts=()
last_label=""

label_for_layout() {
    local layout="$1"

    case "$layout" in
        *English*) echo "EN" ;;
        *Russian*) echo "RU" ;;
        "") return 1 ;;
        *) echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]' ;;
    esac
}

read_snapshot() {
    hyprctl devices -j 2>/dev/null \
        | jq -r '.keyboards[] | [.name, .active_keymap] | @tsv' 2>/dev/null
}

emit_label() {
    local label="$1"

    [ -n "$label" ] || return
    [ "$label" != "$last_label" ] || return

    printf '%s\n' "$label"
    last_label="$label"
}

process_snapshot() {
    local snapshot="$1"
    local name layout first_layout preferred_layout changed_layout label
    local -A next=()

    while IFS=$'\t' read -r name layout; do
        [ -n "$name" ] || continue

        next["$name"]="$layout"
        [ -n "$first_layout" ] || first_layout="$layout"
        [ "$name" != "$KB" ] || preferred_layout="$layout"

        if [ -n "${layouts[$name]+set}" ] && [ "${layouts[$name]}" != "$layout" ]; then
            changed_layout="$layout"
        fi
    done <<< "$snapshot"

    layouts=()
    for name in "${!next[@]}"; do
        layouts["$name"]="${next[$name]}"
    done

    label=$(label_for_layout "${changed_layout:-${preferred_layout:-$first_layout}}") || return
    emit_label "$label"
}

while :; do
    snapshot=$(read_snapshot)
    [ -z "$snapshot" ] || process_snapshot "$snapshot"
    sleep "$INTERVAL"
done
