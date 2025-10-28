#!/bin/sh
# wallpaperchange.sh – dmenu trigger for wallpaper management
# Features:
# - Random wallpaper (different per monitor)
# - Manual selection with preview (uses sxiv)
set -eu

W="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"

# Main menu
choice="$(printf '%s\n' 'Random (different per monitor)' 'Select specific wallpaper' | dmenu -p 'Wallpaper action:' -i)"
[ -z "${choice}" ] && exit 0

case "$choice" in
'Random (different per monitor)')
  # Use wallrotate.sh for random wallpapers
  ~/.local/bin/wallrotate.sh next
  command -v notify-send >/dev/null 2>&1 && notify-send "Wallpaper" "Changed to random images"
  ;;

'Select specific wallpaper')
  # Check if sxiv is installed
  if ! command -v sxiv >/dev/null 2>&1; then
    notify-send "Error" "sxiv not installed. Install with: sudo pacman -S sxiv"
    exit 1
  fi
  
  # Check if wallpaper directory exists
  if [ ! -d "$W" ]; then
    notify-send "Error" "Wallpaper directory not found: $W"
    exit 1
  fi
  
  # Count available wallpapers
  count=$(find -L "$W" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.webp' \) 2>/dev/null | wc -l)
  
  if [ "$count" -eq 0 ]; then
    notify-send "Error" "No wallpapers found in: $W"
    exit 1
  fi
  
  # Launch sxiv in thumbnail mode and get selected image
  # User can:
  # - Navigate with arrow keys
  # - Press 'm' to mark image (or just press Enter on one image)
  # - Press 'q' to exit sxiv
  # The marked/selected image path is returned
  selected=$(find -L "$W" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' -o -iname '*.webp' \) 2>/dev/null | \
    sxiv -t -o 2>/dev/null | head -n1)
  
  # If user selected an image, apply it to all monitors
  if [ -n "${selected:-}" ] && [ -f "$selected" ]; then
    # Detect monitors
    monitors=$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $NF}')
    monitor_count=$(echo "$monitors" | wc -l)
    
    # Apply same wallpaper to all monitors
    if [ "$monitor_count" -gt 0 ]; then
      # Build array of same image repeated for each monitor
      img_args=""
      for mon in $monitors; do
        img_args="$img_args $selected"
      done
      feh --no-fehbg --bg-fill $img_args
    else
      # Fallback: single monitor or no xrandr
      feh --no-fehbg --bg-fill "$selected"
    fi
    
    command -v notify-send >/dev/null 2>&1 && notify-send "Wallpaper" "Set to: $(basename "$selected")"
  else
    # User cancelled or no selection
    exit 0
  fi
  ;;
esac
