#!/usr/bin/env bash
# Wraps swaync-client -swb output into a single icon string for EWW deflisten.
# Input JSON: {"text":"...","alt":"...","class":"..."}

swaync-client -swb 2>/dev/null | while read -r line; do
    alt=$(echo "$line" | jq -r '.alt // "none"')
    case "$alt" in
        notification)                  echo "󰂚" ;;
        none)                          echo "󰂜" ;;
        dnd-notification|dnd-none|inhibited-notification|inhibited-none|dnd-inhibited-notification|dnd-inhibited-none) echo "󰂛" ;;
        *)                             echo "󰂜" ;;
    esac
done
