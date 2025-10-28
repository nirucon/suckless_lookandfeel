#!/usr/bin/env bash
# =====================================================
#  dwm-keybindings.sh — Display formatted DWM keybindings
#  Requirements: gawk, fzf (optional for interactive mode)
# =====================================================

set -euo pipefail

# ==================== Configuration ====================

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/suckless/dwm/config.h"
INTERACTIVE=0
CATEGORY_FILTER=""

# ==================== Parse Arguments ====================

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [CONFIG_FILE]

Display DWM keybindings from config.h in a formatted table.

OPTIONS:
  -i, --interactive     Launch interactive fzf search mode
  -c, --category CAT    Filter by category (Launchers, Layout, Tags, etc.)
  -h, --help            Show this help message
  --no-color            Disable color output

EXAMPLES:
  $(basename "$0")                          # Use default config
  $(basename "$0") /path/to/config.h        # Use custom config
  $(basename "$0") -i                       # Interactive search mode
  $(basename "$0") -c "Launchers"           # Show only Launchers

CATEGORIES:
  Launchers, Layout, Tags, Focus & Stack, Monitors, Scratchpads, System, Misc
EOF
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    -i|--interactive)
      INTERACTIVE=1
      shift
      ;;
    -c|--category)
      CATEGORY_FILTER="$2"
      shift 2
      ;;
    --no-color)
      NO_COLOR=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
    *)
      CONFIG="$1"
      shift
      ;;
  esac
done

# ==================== Validation ====================

# Validate config file exists
if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config.h not found at $CONFIG" >&2
  echo "Tip: Specify path as argument or set XDG_CONFIG_HOME" >&2
  exit 1
fi

# Check for gawk dependency
if ! command -v gawk >/dev/null 2>&1; then
  echo "Error: gawk is required but not installed" >&2
  echo "Install with: sudo pacman -S gawk" >&2
  exit 1
fi

# Check for fzf if interactive mode requested
if [[ $INTERACTIVE -eq 1 ]] && ! command -v fzf >/dev/null 2>&1; then
  echo "Error: fzf is required for interactive mode but not installed" >&2
  echo "Install with: sudo pacman -S fzf" >&2
  exit 1
fi

# ==================== Color Setup ====================

BOLD=""
DIM=""
CYAN=""
GREEN=""
YELLOW=""
BLUE=""
MAGENTA=""
RESET=""

# Enable colors if outputting to terminal and not disabled
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD="$(tput bold 2>/dev/null || true)"
  DIM="$(tput dim 2>/dev/null || true)"
  CYAN="$(tput setaf 6 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"
  YELLOW="$(tput setaf 3 2>/dev/null || true)"
  BLUE="$(tput setaf 4 2>/dev/null || true)"
  MAGENTA="$(tput setaf 5 2>/dev/null || true)"
  RESET="$(tput sgr0 2>/dev/null || true)"
fi

# ==================== Detect MODKEY ====================

MODKEY_DEF="$(awk '/^#define[ \t]+MODKEY[ \t]+/ {print $3; exit}' "$CONFIG" || true)"
MODKEY_DEF="${MODKEY_DEF:-Mod4Mask}"

# ==================== AWK Parser ====================

awkfile="$(mktemp)"
trap 'rm -f "$awkfile"' EXIT

cat >"$awkfile" <<'AWK'
# ================= AWK PROGRAM =======================

function trim(s) {
  sub(/^[ \t\r\n]+/, "", s)
  sub(/[ \t\r\n]+$/, "", s)
  return s
}

function pretty_mod(m) {
  gsub(/MODKEY/, MODKEY_DEF, m)
  gsub(/Mod4Mask/, "Super", m)
  gsub(/ShiftMask/, "Shift", m)
  gsub(/ControlMask/, "Ctrl", m)
  gsub(/Mod1Mask/, "Alt", m)
  gsub(/\|/, " + ", m)
  return m
}

function pretty_key(k) {
  sub(/^XK_/, "", k)
  
  # Special keys mapping
  if (k == "Return") return "Enter"
  if (k == "space" || k == "Space") return "Space"
  if (k == "Escape") return "Esc"
  if (k == "Tab") return "Tab"
  if (k == "BackSpace") return "Backspace"
  if (k == "comma") return ","
  if (k == "period") return "."
  if (k == "semicolon") return ";"
  if (k == "Print") return "Print"
  
  return k
}

function simplify_arg(arg) {
  # Extract meaningful parts from arguments
  if (arg ~ /^\{\.v = /) {
    sub(/^\{\.v = /, "", arg)
    sub(/ \}$/, "", arg)
    
    # Handle command arrays
    if (arg ~ /cmd/) {
      if (arg ~ /stcmd/) return "st (terminal)"
      if (arg ~ /alacrittycmd/) return "alacritty (terminal)"
      if (arg ~ /bravecmd/) return "brave (browser)"
      if (arg ~ /dmenucmd/) return "dmenu (launcher)"
      if (arg ~ /rofiruncmd/) return "rofi run"
      if (arg ~ /keybindingscmd/) return "keybindings viewer (interactive)"
      if (arg ~ /lockcmd/) return "lock screen"
      if (arg ~ /fmcmd/) return "file manager"
      if (arg ~ /scratchpadcmd/) return "scratchpad terminal"
      if (arg ~ /br_up/) return "brightness up"
      if (arg ~ /br_down/) return "brightness down"
      if (arg ~ /vol_up/) return "volume up"
      if (arg ~ /vol_down/) return "volume down"
      if (arg ~ /vol_toggle/) return "volume mute toggle"
      if (arg ~ /mic_toggle/) return "mic mute toggle"
      if (arg ~ /ss_select/) return "screenshot region"
      if (arg ~ /ss_full/) return "screenshot fullscreen"
      if (arg ~ /ss_flameshot/) return "screenshot flameshot"
      if (arg ~ /wallnext/) return "next wallpaper"
    }
    
    # Handle layout references
    if (arg ~ /&layouts\[/) {
      num = arg
      sub(/.*&layouts\[/, "", num)
      sub(/\].*/, "", num)
      return "layout " num
    }
  }
  
  # Handle SHCMD
  if (arg ~ /SHCMD/) {
    cmd = arg
    sub(/.*SHCMD\("/, "", cmd)
    sub(/"\).*/, "", cmd)
    return cmd
  }
  
  # Handle simple numeric arguments
  if (arg ~ /^\{\.i = [+-]?[0-9]+ \}$/) {
    sub(/^\{\.i = /, "", arg)
    sub(/ \}$/, "", arg)
    if (arg == "+1") return "next"
    if (arg == "-1") return "previous"
    return arg
  }
  
  # Handle float arguments
  if (arg ~ /^\{\.f = [+-]?[0-9.]+\}$/) {
    sub(/^\{\.f = /, "", arg)
    sub(/\}$/, "", arg)
    if (arg ~ /^-/) return "decrease " arg
    if (arg ~ /^\+/) return "increase " arg
    return arg
  }
  
  # Handle tag arguments
  if (arg ~ /^tag [0-9]+$/) return arg
  if (arg ~ /^move to [0-9]+$/) return arg
  if (arg ~ /^add\/remove [0-9]+$/) return arg
  
  # Empty or {0}
  if (arg == "{0}" || arg == "") return "—"
  
  return arg
}

function category_of(fn, act) {
  # System commands
  if (fn == "killclient" || fn == "quit" || fn == "restart" || 
      fn == "quitprompt" || fn == "lock" || fn == "lockscreen")
    return "System"
  
  # Launchers
  if (fn == "spawn") return "Launchers"
  
  # Layout management
  if (fn == "setlayout" || fn == "togglefloating" || fn == "togglebar")
    return "Layout"
  
  # Tag operations
  if (fn == "view" || fn == "toggleview" || fn == "tag" || fn == "toggletag" ||
      act ~ /^view / || act ~ /^toggleview/ || act ~ /^tag / || act ~ /^toggletag/)
    return "Tags"
  
  # Focus and stack management
  if (fn == "focusstack" || fn == "rotatestack" || fn == "zoom" || 
      fn == "setmfact" || fn == "incnmaster" || fn == "setcfact" || 
      fn == "pushdown" || fn == "pushup" || fn == "movestack")
    return "Focus & Stack"
  
  # Monitor operations
  if (fn == "focusmon" || fn == "tagmon" || fn == "zoommon")
    return "Monitors"
  
  # Scratchpad
  if (fn == "togglescratch" || fn == "scratchpad_show" || 
      fn == "scratchpad_hide" || fn == "scratchpad_remove")
    return "Scratchpads"
  
  return "Misc"
}

function print_border() {
  print "+------------------------+-------------+------------------+------------------------------------------+"
}

function print_header() {
  print "| " CYAN "Modifiers" RESET "              | " CYAN "Key" RESET "         | " CYAN "Function" RESET "         | " CYAN "Description" RESET "                             |"
}

function append_row(cat, mods, key, fn, arg) {
  # Simplify argument for better readability
  simple_arg = simplify_arg(arg)
  
  # Store for table display
  store[cat] = store[cat] sprintf("| %-33s | %-23s | %-27s | %-40s |\n", 
    mods, key, fn, simple_arg)
  
  # Also store raw data for fzf/filtering (tab-separated)
  if (OUTPUT_FORMAT == "tsv") {
    print cat "\t" mods "\t" key "\t" fn "\t" simple_arg
  }
  
  counts[cat]++
  total_count++
}

function strip_comments(s) {
  sub(/\/\/.*/, "", s)
  gsub(/\/\*([^*]|\*[^\/])*\*\//, "", s)
  return s
}

function extract_inner(s,   i, c, depth, start, inner) {
  start = index(s, "{")
  if (!start) return ""
  
  depth = 0
  inner = ""
  
  for (i = start; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "{") {
      depth++
      if (depth > 1) inner = inner c
      continue
    }
    if (c == "}") {
      depth--
      if (depth == 0) break
      inner = inner c
      continue
    }
    if (depth >= 1) inner = inner c
  }
  
  return trim(inner)
}

function split_fields(inner, f1, f2, f3, f4,   i, c, depthB, depthP, depthS, depthQ, pos1, pos2, pos3) {
  depthB = depthP = depthS = depthQ = 0
  pos1 = pos2 = pos3 = 0
  
  for (i = 1; i <= length(inner); i++) {
    c = substr(inner, i, 1)
    
    # Track quote depth
    if (c == "\"" && substr(inner, i-1, 1) != "\\") {
      depthQ = 1 - depthQ
    }
    if (depthQ) continue
    
    # Track bracket depths
    if (c == "{") depthB++
    else if (c == "}") depthB--
    else if (c == "(") depthP++
    else if (c == ")") depthP--
    else if (c == "[") depthS++
    else if (c == "]") depthS--
    else if (c == "," && depthB == 0 && depthP == 0 && depthS == 0) {
      if (pos1 == 0) pos1 = i
      else if (pos2 == 0) pos2 = i
      else if (pos3 == 0) { pos3 = i; break }
    }
  }
  
  if (pos1 == 0 || pos2 == 0 || pos3 == 0) return 0
  
  f1 = trim(substr(inner, 1, pos1 - 1))
  f2 = trim(substr(inner, pos1 + 1, pos2 - pos1 - 1))
  f3 = trim(substr(inner, pos2 + 1, pos3 - pos2 - 1))
  f4 = trim(substr(inner, pos3 + 1))
  
  # Remove trailing comma
  sub(/,[ \t]*$/, "", f4)
  
  fields1 = f1; fields2 = f2; fields3 = f3; fields4 = f4
  return 1
}

BEGIN {
  total_count = 0
  
  if (OUTPUT_FORMAT == "tsv") {
    # Skip header for TSV output (used by fzf)
  } else {
    print ""
    print BOLD GREEN "DWM Keybindings Overview" RESET
    print DIM "Configuration: " RESET SRC
    print DIM "Modifier key: " RESET MODKEY_DEF " (Super/Win)"
    print ""
  }
}

# Detect keys[] array
/^[[:space:]]*static[[:space:]]+(const[[:space:]]+)?Key[[:space:]]+keys[[:space:]]*\[[^]]*\][[:space:]]*=/ {
  inblock = 1
  next
}

inblock && /^\};[[:space:]]*$/ {
  inblock = 0
  next
}

# Parse keybindings
inblock {
  raw = $0
  line = strip_comments(raw)
  gsub(/,[ \t]*\.\.\.[ \t]*/, ",", line)
  
  if (line ~ /^[ \t]*$/) next
  
  # Handle TAGKEYS macro expansion
  if (line ~ /TAGKEYS\(/) {
    sym = line
    sub(/.*TAGKEYS\(\s*/, "", sym)
    sub(/\s*,.*/, "", sym)
    
    tagidx = line
    sub(/.*TAGKEYS\(\s*XK_[^,]+,\s*/, "", tagidx)
    sub(/\s*\).*/, "", tagidx)
    
    keyname = pretty_key(sym)
    tagnum = tagidx + 1
    mods = "MODKEY"
    
    # Check for custom modifier prefix
    if (line ~ /^[ \t]*\{[ \t]*[^,]+,[ \t]*TAGKEYS/) {
      mods = line
      sub(/^[ \t]*\{\s*/, "", mods)
      sub(/\s*,\s*TAGKEYS.*/, "", mods)
    }
    
    append_row(category_of("view", "view"), 
               pretty_mod(mods), keyname, "view", "tag " tagnum)
    append_row(category_of("toggleview", ""), 
               pretty_mod(mods " | ControlMask"), keyname, "toggleview", "tag " tagnum)
    append_row(category_of("tag", ""), 
               pretty_mod(mods " | ShiftMask"), keyname, "tag", "move to " tagnum)
    append_row(category_of("toggletag", ""), 
               pretty_mod(mods " | ControlMask | ShiftMask"), keyname, "toggletag", "add/remove " tagnum)
    next
  }
  
  # Parse regular keybindings
  if (line ~ /^[ \t]*\{/) {
    inner = extract_inner(line)
    if (inner == "") next
    
    ok = split_fields(inner)
    if (!ok) next
    
    mods_raw = fields1
    key_raw = fields2
    fn = fields3
    arg = fields4
    
    keyname = key_raw
    if (key_raw ~ /^XK_/) keyname = pretty_key(key_raw)
    
    append_row(category_of(fn, fn), pretty_mod(mods_raw), keyname, fn, arg)
    next
  }
}

END {
  if (OUTPUT_FORMAT == "tsv") {
    # TSV output complete
    exit
  }
  
  # Category order
  cats[1] = "Launchers"
  cats[2] = "Layout"
  cats[3] = "Tags"
  cats[4] = "Focus & Stack"
  cats[5] = "Monitors"
  cats[6] = "Scratchpads"
  cats[7] = "System"
  cats[8] = "Misc"
  
  # Print each category
  for (i = 1; i <= 8; i++) {
    c = cats[i]
    
    # Apply category filter if specified
    if (CATEGORY_FILTER != "" && c != CATEGORY_FILTER) continue
    
    if (counts[c] > 0) {
      print ""
      print BOLD YELLOW "▸ " c RESET
      print_border()
      print_header()
      print_border()
      printf "%s", store[c]
      print_border()
    }
  }
  
  print ""
  print DIM "Total keybindings: " RESET total_count
  print ""
  print DIM "Tip: Use " RESET BOLD "-i" RESET DIM " flag for interactive fuzzy search with fzf" RESET
  print DIM "     Use " RESET BOLD "-c CategoryName" RESET DIM " to filter by category" RESET
  print DIM "     Use " RESET BOLD "--help" RESET DIM " for more options" RESET
  print ""
}

# ================= END AWK ==========================
AWK

# ==================== Main Execution ====================

if [[ $INTERACTIVE -eq 1 ]]; then
  # Interactive mode with fzf
  echo "Parsing keybindings from: $CONFIG" >&2
  echo "Loading interactive search..." >&2
  echo "" >&2
  
  # Generate TSV data for fzf
  tsv_data=$(gawk \
    -v MODKEY_DEF="$MODKEY_DEF" \
    -v OUTPUT_FORMAT="tsv" \
    -f "$awkfile" \
    "$CONFIG")
  
  # Launch fzf with preview
  selection=$(echo "$tsv_data" | fzf \
    --delimiter='\t' \
    --with-nth=1,2,3,4,5 \
    --header="DWM Keybindings - Search and filter (ESC to quit)" \
    --preview='echo {} | cut -f1-5 | column -t -s $'"'"'\t'"'"' -N "Category,Modifiers,Key,Function,Description"' \
    --preview-window=up:3:wrap \
    --bind='ctrl-/:toggle-preview' \
    --height=100% \
    --color='header:italic:underline,prompt:cyan,pointer:green' \
    --prompt="Search keybindings: " \
    --pointer="▶" \
    --marker="✓")
  
  if [[ -n "$selection" ]]; then
    echo ""
    echo "Selected keybinding:"
    echo "$selection" | column -t -s $'\t' -N "Category,Modifiers,Key,Function,Description"
    echo ""
  fi
  
elif [[ -n "$CATEGORY_FILTER" ]]; then
  # Category filter mode
  gawk \
    -v MODKEY_DEF="$MODKEY_DEF" \
    -v BOLD="$BOLD" \
    -v DIM="$DIM" \
    -v CYAN="$CYAN" \
    -v GREEN="$GREEN" \
    -v YELLOW="$YELLOW" \
    -v RESET="$RESET" \
    -v SRC="$CONFIG" \
    -v CATEGORY_FILTER="$CATEGORY_FILTER" \
    -f "$awkfile" \
    "$CONFIG"
  
else
  # Standard table output mode
  gawk \
    -v MODKEY_DEF="$MODKEY_DEF" \
    -v BOLD="$BOLD" \
    -v DIM="$DIM" \
    -v CYAN="$CYAN" \
    -v GREEN="$GREEN" \
    -v YELLOW="$YELLOW" \
    -v RESET="$RESET" \
    -v SRC="$CONFIG" \
    -f "$awkfile" \
    "$CONFIG"
fi
