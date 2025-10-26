#!/usr/bin/env bash
# Clipboard history menu for dwm
# Shows text history (with timestamps + 20 char preview) + screenshot history in dmenu
# Dependencies: xclip, sxiv, dmenu

set -euo pipefail

# Paths
CLIP_HISTORY="$HOME/.cache/clip-text.log"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"

# Ensure clip history file exists
touch "$CLIP_HISTORY"

# Temporary file for menu items
MENU_FILE=$(mktemp)
trap 'rm -f "$MENU_FILE"' EXIT

# Build menu
{
  echo "━━━ TEXT (last 5) ━━━"

  # Get all text entries (newest first, max 5)
  if [ -s "$CLIP_HISTORY" ]; then
    tac "$CLIP_HISTORY" | while IFS='|' read -r timestamp text; do
      # Trim whitespace from text
      text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # Truncate to 60 chars for display
      if [ ${#text} -gt 60 ]; then
        preview="${text:0:60}..."
      else
        preview="$text"
      fi

      # Format: 📝 YYYY-MM-DD HH:MM - preview
      echo "📝 $timestamp - $preview"
    done
  else
    echo "  (no history)"
  fi

  echo ""
  echo "━━━ SCREENSHOTS (last 5) ━━━"

  # Get last 5 screenshots (newest first)
  # Use -L to follow symlinks
  if [ -d "$SCREENSHOT_DIR" ] && find -L "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "*.png" -print -quit 2>/dev/null | grep -q .; then
    find -L "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "*.png" -printf "%T@ %p\n" 2>/dev/null |
      sort -rn | head -n 5 | while read -r timestamp filepath; do
      filename=$(basename "$filepath")
      size=$(du -h "$filepath" | cut -f1)
      echo "🖼️  $filename ($size)"
    done
  else
    echo "  (no screenshots)"
  fi
} >"$MENU_FILE"

# Show dmenu and get selection
selection=$(cat "$MENU_FILE" | dmenu -i -l 12 -p "Clipboard:" -nb "#0f0f10" -nf "#a8a8a8" -sb "#3a3a3d" -sf "#e5e5e5" -fn "JetBrainsMono Nerd Font:size=11")

# Handle empty selection
if [ -z "$selection" ]; then
  exit 0
fi

# Process selection
if [[ "$selection" =~ ^📝 ]]; then
  # Text selection - extract timestamp from selection
  # Format: "📝 YYYY-MM-DD HH:MM - preview..."
  # We need to find the matching line in history by timestamp

  # Extract timestamp from selection (remove emoji and everything after " - ")
  selected_timestamp=$(echo "$selection" | sed -E 's/^📝[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}).*/\1/')

  # Find full text from history by matching timestamp
  # Read in same order as displayed (newest first)
  full_text=""
  while IFS='|' read -r timestamp text; do
    # Trim timestamp
    timestamp=$(echo "$timestamp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$timestamp" = "$selected_timestamp" ]; then
      # Found matching entry, get full text
      full_text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      break
    fi
  done < <(tac "$CLIP_HISTORY")

  if [ -n "$full_text" ]; then
    # Copy to clipboard
    echo -n "$full_text" | xclip -selection clipboard
    notify-send "Clipboard" "Text copied"
  else
    notify-send "Clipboard" "Could not find text"
  fi

elif [[ "$selection" =~ ^🖼️ ]]; then
  # Screenshot selection - extract filename
  filename=$(echo "$selection" | sed -E 's/^🖼️[[:space:]]+([^[:space:]]+).*/\1/')
  filepath="$SCREENSHOT_DIR/$filename"

  if [ -f "$filepath" ]; then
    # Copy image to clipboard
    xclip -selection clipboard -t image/png -i "$filepath"
    notify-send "Clipboard" "Image copied to clipboard"

    # Open in sxiv
    sxiv "$filepath" &
  else
    notify-send "Clipboard" "Could not find file: $filename"
  fi
fi
