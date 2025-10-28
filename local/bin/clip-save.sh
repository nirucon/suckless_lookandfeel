#!/usr/bin/env bash
# Save current clipboard selection to history with timestamp
# Usage: clip-save.sh
# Format: YYYY-MM-DD HH:MM | text content

set -euo pipefail

CLIP_HISTORY="$HOME/.cache/clip-text.log"
MAX_LINES=5 # Keep only last 5 entries

# Ensure directory exists
mkdir -p "$(dirname "$CLIP_HISTORY")"
touch "$CLIP_HISTORY"

# Get current clipboard content
clip_content=$(xclip -o -selection clipboard 2>/dev/null || true)

# Skip if empty
if [ -z "$clip_content" ]; then
  exit 0
fi

# Truncate to single line (replace newlines with spaces)
clip_content=$(echo "$clip_content" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')

# Truncate to max 200 chars for storage
if [ ${#clip_content} -gt 200 ]; then
  clip_content="${clip_content:0:200}"
fi

# Get current timestamp
timestamp=$(date '+%Y-%m-%d %H:%M')

# Create entry with timestamp
entry="$timestamp | $clip_content"

# Check if this exact content already exists (check only the text part after |)
if [ -f "$CLIP_HISTORY" ]; then
  while IFS='|' read -r ts text; do
    # Trim whitespace from text part
    text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ "$text" = "$clip_content" ]; then
      # Content already exists, skip saving
      exit 0
    fi
  done <"$CLIP_HISTORY"
fi

# Append to history
echo "$entry" >>"$CLIP_HISTORY"

# Keep only last MAX_LINES entries
tail -n "$MAX_LINES" "$CLIP_HISTORY" >"$CLIP_HISTORY.tmp"
mv "$CLIP_HISTORY.tmp" "$CLIP_HISTORY"

notify-send "Clipboard" "Sparat till historik"
