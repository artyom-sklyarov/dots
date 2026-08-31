#!/bin/sh


WALL="$HOME/.local/share/Steam/steamapps/workshop/content/431960/3627262049/视频.mp4"
SOCK="${XDG_RUNTIME_DIR:-/tmp}/mpvpaper.sock"

pgrep -x mpvpaper >/dev/null && exit 0

fails=0
while :; do
    start=$(date +%s)
    mpvpaper -o "no-audio loop hwdec=auto input-ipc-server=$SOCK" '*' "$WALL"
    code=$?
    [ "$code" -eq 0 ] && exit 0
    if [ $(($(date +%s) - start)) -lt 30 ]; then
        fails=$((fails + 1))
        [ "$fails" -ge 5 ] && exit "$code"
    else
        fails=0
    fi
    sleep 1
done
