#!/usr/bin/env bash
# Save current clipboard selection to history
# Usage: clip-save.sh

set -euo pipefail

CLIP_HISTORY="$HOME/.cache/clip-text.log"
MAX_LINES=50  # Keep last 50 entries

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

# Check if this exact content already exists (avoid duplicates)
if grep -Fxq "$clip_content" "$CLIP_HISTORY" 2>/dev/null; then
  exit 0
fi

# Append to history
echo "$clip_content" >> "$CLIP_HISTORY"

# Keep only last MAX_LINES entries
tail -n "$MAX_LINES" "$CLIP_HISTORY" > "$CLIP_HISTORY.tmp"
mv "$CLIP_HISTORY.tmp" "$CLIP_HISTORY"

notify-send "Clipboard" "Sparat till historik"
