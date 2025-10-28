#!/bin/bash
# wallpaperchange_dmenu.sh – dmenu-only wallpaper selector (no sxiv needed)
# Simpler alternative that lists wallpapers in dmenu
set -eu

W="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"

# Main menu
choice="$(printf '%s\n' 'Random (different per monitor)' 'Select from list (dmenu)' 'Browse with images (sxiv)' | dmenu -p 'Wallpaper:' -i)"
[ -z "${choice}" ] && exit 0

case "$choice" in
'Random (different per monitor)')
  # Use wallrotate.sh for random wallpapers
  if [ -x "$HOME/.local/bin/wallrotate.sh" ]; then
    "$HOME/.local/bin/wallrotate.sh" next
    command -v notify-send >/dev/null 2>&1 && notify-send "Wallpaper" "Changed to random images"
  else
    command -v notify-send >/dev/null 2>&1 && notify-send "Error" "wallrotate.sh not found"
    exit 1
  fi
  ;;

'Select from list (dmenu)')
  # List wallpapers in dmenu (filename only, no preview)
  if [ ! -d "$W" ]; then
    command -v notify-send >/dev/null 2>&1 && notify-send "Error" "Wallpaper directory not found: $W"
    exit 1
  fi
  
  # Get list of wallpapers with just filenames
  selected=$(find -L "$W" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.webp' \) 2>/dev/null | \
    sed "s|$W/||" | \
    sort | \
    dmenu -l 20 -p 'Choose wallpaper:' -i)
  
  [ -z "${selected}" ] && exit 0
  
  # Reconstruct full path
  full_path="$W/$selected"
  
  if [ -f "$full_path" ]; then
    # Apply to all monitors
    monitor_count=$(xrandr --listmonitors 2>/dev/null | awk 'NR>1' | wc -l)
    
    if [ "$monitor_count" -gt 1 ]; then
      mapfile -t monitors < <(xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $NF}')
      img_array=()
      for mon in "${monitors[@]}"; do
        img_array+=("$full_path")
      done
      feh --no-fehbg --bg-fill "${img_array[@]}"
    else
      feh --no-fehbg --bg-fill "$full_path"
    fi
    
    command -v notify-send >/dev/null 2>&1 && notify-send "Wallpaper" "Set to: $selected"
  fi
  ;;

'Browse with images (sxiv)')
  # Use sxiv for visual browsing
  if ! command -v sxiv >/dev/null 2>&1; then
    command -v notify-send >/dev/null 2>&1 && notify-send "Error" "sxiv not installed. Install: sudo pacman -S sxiv"
    exit 1
  fi
  
  if [ ! -d "$W" ]; then
    command -v notify-send >/dev/null 2>&1 && notify-send "Error" "Wallpaper directory not found: $W"
    exit 1
  fi
  
  tmpfile=$(mktemp)
  find -L "$W" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.webp' \) 2>/dev/null > "$tmpfile"
  
  count=$(wc -l < "$tmpfile")
  if [ "$count" -eq 0 ]; then
    command -v notify-send >/dev/null 2>&1 && notify-send "Error" "No wallpapers found in: $W"
    rm -f "$tmpfile"
    exit 1
  fi
  
  command -v notify-send >/dev/null 2>&1 && notify-send -t 5000 "Wallpaper (sxiv)" "1. Navigate with arrows\n2. Press 'm' to mark\n3. Press 'q' to apply"
  
  selected=$(cat "$tmpfile" | sxiv -t -i -o 2>/dev/null | head -n1)
  rm -f "$tmpfile"
  
  if [ -n "${selected:-}" ] && [ -f "$selected" ]; then
    monitor_count=$(xrandr --listmonitors 2>/dev/null | awk 'NR>1' | wc -l)
    
    if [ "$monitor_count" -gt 1 ]; then
      mapfile -t monitors < <(xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $NF}')
      img_array=()
      for mon in "${monitors[@]}"; do
        img_array+=("$selected")
      done
      feh --no-fehbg --bg-fill "${img_array[@]}"
    else
      feh --no-fehbg --bg-fill "$selected"
    fi
    
    command -v notify-send >/dev/null 2>&1 && notify-send "Wallpaper" "Set to: $(basename "$selected")"
  fi
  ;;
esac
