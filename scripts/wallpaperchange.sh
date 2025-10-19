#!/bin/sh
# wallpaperchange.sh — dmenu trigger for immediate random wallpaper
set -eu

choice="$(printf '%s\n' 'Next (random)' | dmenu -p 'Wallpaper action:' -i)"
[ -z "${choice}" ] && exit 0

case "$choice" in
'Next (random)')
  ~/.local/bin/wallrotate.sh next
  command -v notify-send >/dev/null 2>&1 && notify-send "Wallpaper" "Changed to a random image"
  ;;
esac
