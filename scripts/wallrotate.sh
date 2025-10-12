#!/bin/bash
W="$HOME/Pictures/Wallpapers"
LOG="$HOME/.cache/wallrotate.log"
mkdir -p "$(dirname "$LOG")"

# ────────────────────────────────────────────────
# Function to pick a random image from folder or symlink
# -L makes find follow symlinks
# ────────────────────────────────────────────────
pick() {
  find -L "$W" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.webp' \) 2>/dev/null | shuf -n1
}

# ────────────────────────────────────────────────
# Function to apply wallpaper on all monitors
# ────────────────────────────────────────────────
apply_wall() {
  img="$(pick)"
  if [ -z "$img" ]; then
    echo "$(date '+%F %T') ⚠️  No images found in $W" >>"$LOG"
    return 1
  fi

  echo "$(date '+%F %T') 🖼️  Setting wallpaper: $img" >>"$LOG"

  # Detect monitors
  mapfile -t heads < <(xrandr --listmonitors 2>/dev/null | awk 'NR>1 {gsub(":","",$1); print $1}')

  if [ "${#heads[@]}" -eq 0 ]; then
    # Single monitor or fallback
    nitrogen --set-zoom-fill "$img" --save
  else
    # Apply to all monitors
    for h in "${heads[@]}"; do
      nitrogen --set-zoom-fill "$img" --head="$h" --save
    done
  fi
}

# ────────────────────────────────────────────────
# Initial wallpaper
# ────────────────────────────────────────────────
apply_wall

# ────────────────────────────────────────────────
# Rotation loop – every 900 seconds (15 minutes)
# ────────────────────────────────────────────────
while sleep 900; do
  apply_wall
done
