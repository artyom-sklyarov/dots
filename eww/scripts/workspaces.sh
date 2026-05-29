#!/bin/sh

last=

hyprland-workspaces ALL | while IFS= read -r line; do
    [ "$line" = "$last" ] && continue
    printf '%s\n' "$line"
    last=$line
done
