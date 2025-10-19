#!/bin/bash
# wallrotate.sh — Wallpaper daemon for DWM/X11 (via xinit)
# - No args  -> start daemon (15 min rotation)
# - next     -> immediate random wallpaper (does not disturb daemon)
# - random   -> alias for next
set -euo pipefail

W="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}" # default dir
LOG="$HOME/.cache/wallrotate.log"
LOCK="$HOME/.cache/wallrotate.lock"
mkdir -p "$(dirname "$LOG")"

timestamp() { date '+%F %T'; }
log() { echo "$(timestamp) $*" >>"$LOG"; }

# Pick a random image (follows symlinks)
pick_random() {
  find -L "$W" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.webp' \) \
    2>/dev/null | shuf -n1
}

# Apply wallpaper to all monitors using Nitrogen
apply_wallpaper() {
  local img="$(pick_random || true)"
  if [ -z "${img:-}" ]; then
    log "⚠️  No images found in $W"
    return 1
  fi
  log "🖼️  Setting wallpaper: $img"

  # Detect monitors
  mapfile -t heads < <(xrandr --listmonitors 2>/dev/null | awk 'NR>1 {gsub(":","",$1); print $1}')

  if [ "${#heads[@]}" -eq 0 ]; then
    nitrogen --set-zoom-fill "$img" --save
  else
    for h in "${heads[@]}"; do
      nitrogen --set-zoom-fill "$img" --head="$h" --save
    done
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [daemon|next|random]

  daemon       Start background rotation (default)
  next/random  Immediately switch to a random wallpaper

Environment:
  WALLPAPER_DIR  Override wallpaper folder (default: $HOME/Pictures/Wallpapers)
EOF
}

cmd="${1:-daemon}"
case "$cmd" in
next | random)
  apply_wallpaper
  exit $?
  ;;
daemon) ;;
*)
  usage
  exit 2
  ;;
esac

# Daemon mode — single instance via flock
exec 9>"$LOCK"
if ! flock -n 9; then
  log "ℹ️  wallrotate.sh already running; exiting."
  exit 0
fi

apply_wallpaper || true

# Rotate every 900 seconds (15 min) — stable timing
while :; do
  sleep 900 &
  spid=$!
  wait "$spid" 2>/dev/null || true
  apply_wallpaper || true
done
