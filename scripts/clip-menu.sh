#!/usr/bin/env bash
# Clipboard history menu for dwm
# Shows text history + screenshot history in dmenu
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
  echo "━━━ TEXT (5 latest) ━━━"

  # Get last 5 text entries (newest first)
  if [ -s "$CLIP_HISTORY" ]; then
    tail -n 5 "$CLIP_HISTORY" | tac | while IFS= read -r line; do
      # Truncate to 60 chars for display
      if [ ${#line} -gt 60 ]; then
        echo "📝 ${line:0:57}..."
      else
        echo "📝 $line"
      fi
    done
  else
    echo "  (no history)"
  fi

  echo ""
  echo "━━━ SCREENSHOTS (5 latest) ━━━"

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
  # Text selection - find full text from history
  display_text="${selection#📝 }"                                 # Remove emoji prefix
  display_text="${display_text%...}"                             # Remove trailing ...
  display_text=$(echo "$display_text" | sed 's/^[[:space:]]*//') # Trim leading spaces

  # Find matching line in history (search from end)
  full_text=$(tac "$CLIP_HISTORY" | grep -F "$display_text" | head -n1 || echo "")

  if [ -n "$full_text" ]; then
    # Copy to clipboard
    echo -n "$full_text" | xclip -selection clipboard
    notify-send "Clipboard" "Text copied to clipboard"
  else
    notify-send "Clipboard" "Can't find complete text"
  fi

elif [[ "$selection" =~ ^🖼️ ]]; then
  # Screenshot selection - extract filename
  filename=$(echo "$selection" | sed -E 's/^🖼️[[:space:]]+([^[:space:]]+).*/\1/')
  filepath="$SCREENSHOT_DIR/$filename"

  if [ -f "$filepath" ]; then
    # Open in sxiv
    sxiv "$filepath" &
  else
    notify-send "Clipboard" "Can't find file: $filename"
  fi
fi
