#!/bin/sh


WALL="$HOME/.local/share/wallpapers/wallpaper-3440-hevc.mp4"
SOCK="${XDG_RUNTIME_DIR:-/tmp}/mpvpaper.sock"

pgrep -x mpvpaper >/dev/null && exit 0

fails=0
while :; do
    start=$(date +%s)
    __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json \
    VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json \
    mpvpaper -o "no-audio loop hwdec=vaapi,vaapi-copy vaapi-device=/dev/dri/renderD128 demuxer-max-bytes=32MiB demuxer-max-back-bytes=8MiB input-ipc-server=$SOCK" '*' "$WALL"
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
