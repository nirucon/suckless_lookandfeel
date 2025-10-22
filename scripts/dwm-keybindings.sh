#!/usr/bin/env bash
# =====================================================
#  dwm-keybindings.sh — Show nicely formatted DWM keys
#  Requires: gawk
# =====================================================

set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/suckless/dwm/config.h"
if [[ $# -ge 1 && "$1" != "--no-color" && "$1" != "--with-line" ]]; then
  CONFIG="$1"
fi
[[ -f "$CONFIG" ]] || {
  echo "config.h not found at $CONFIG" >&2
  exit 1
}

command -v gawk >/dev/null 2>&1 || {
  echo "Please install gawk (sudo pacman -S gawk)" >&2
  exit 1
}

# Colors
BOLD=""
DIM=""
RESET=""
if [[ -t 1 ]]; then
  BOLD="$(tput bold 2>/dev/null || true)"
  DIM="$(tput dim 2>/dev/null || true)"
  RESET="$(tput sgr0 2>/dev/null || true)"
fi

# Detect MODKEY from #define (fallback to Mod4Mask)
MODKEY_DEF="$(awk '/^#define[ \t]+MODKEY[ \t]+/ {print $3; exit}' "$CONFIG" || true)"
MODKEY_DEF="${MODKEY_DEF:-Mod4Mask}"

awkfile="$(mktemp)"
trap 'rm -f "$awkfile"' EXIT

cat >"$awkfile" <<'AWK'
# ================= AWK PROGRAM =======================
function trim(s){sub(/^[ \t\r\n]+/,"",s);sub(/[ \t\r\n]+$/,"",s);return s}
function pretty_mod(m){
  gsub(/MODKEY/, MODKEY_DEF, m)
  gsub(/Mod4Mask/,"Super",m)
  gsub(/ShiftMask/,"Shift",m)
  gsub(/ControlMask/,"Ctrl",m)
  gsub(/Mod1Mask/,"Alt",m)
  gsub(/\|/," + ",m)
  return m
}
function pretty_key(k){
  sub(/^XK_/,"",k)
  if(k=="Return") return "Enter"
  if(k=="space"||k=="Space") return "Space"
  if(k=="Escape") return "Esc"
  if(k=="Tab") return "Tab"
  if(k=="BackSpace") return "Backspace"
  if(k=="comma") return ","
  if(k=="period") return "."
  if(k=="semicolon") return ";"
  return k
}
function category_of(fn, act){
  if(fn=="spawn") return "Launchers"
  if(fn=="setlayout"||fn=="togglefloating"||fn=="togglebar") return "Layout"
  if(fn=="view"||fn=="toggleview"||fn=="tag"||fn=="toggletag") return "Tags"
  if(fn=="focusstack"||fn=="rotatestack"||fn=="zoom"||fn=="setmfact"||fn=="incnmaster"||fn=="setcfact"||fn=="pushdown"||fn=="pushup"||fn=="movestack") return "Focus & Stack"
  if(fn=="focusmon"||fn=="tagmon"||fn=="zoommon") return "Monitors"
  if(fn=="togglescratch"||fn=="scratchpad_show"||fn=="scratchpad_hide"||fn=="scratchpad_remove") return "Scratchpads"
  if(fn=="killclient"||fn=="quit"||fn=="restart"||fn=="quitprompt"||fn=="lock"||fn=="lockscreen") return "System"
  if(act ~ /^view / || act ~ /^toggleview/ || act ~ /^tag / || act ~ /^toggletag/) return "Tags"
  return "Misc"
}
function border(){
  print "+----------------------+------------+------------------+------------------------------------------+--------+"
}
function header(){
  print "| Modifiers            | Key        | Function         | Argument                                 | Line   |"
}
function append_row(cat, mods, key, fn, arg, ln){
  store[cat] = store[cat] sprintf("| %-20s | %-10s | %-16s | %-40s | %-6s |\n", mods, key, fn, arg, ln)
  counts[cat]++
}
# Strip // and /*...*/ (inline)
function strip_comments(s){
  sub(/\/\/.*/,"",s)
  gsub(/\/\*([^*]|\*[^\/])*\*\//,"",s)
  return s
}
# Extract inner of outermost {...} while handling nested braces
function extract_inner(s,   i,c,depth,start,inner){
  start = index(s, "{")
  if(!start) return ""
  depth=0
  inner=""
  for(i=start; i<=length(s); i++){
    c=substr(s,i,1)
    if(c=="{"){ depth++; if(depth>1) inner=inner c; continue }
    if(c=="}"){ depth--; if(depth==0) break; inner=inner c; continue }
    if(depth>=1) inner=inner c
  }
  return trim(inner)
}
# Split inner by top-level commas into 4 fields (mods,key,func,arg)
function split_fields(inner, f1,f2,f3,f4,   i,c,depthB,depthP,depthS,depthQ,pos1,pos2,pos3){
  depthB=depthP=depthS=0; depthQ=0
  pos1=pos2=pos3=0
  for(i=1;i<=length(inner);i++){
    c=substr(inner,i,1)
    if(c=="\"" && substr(inner,i-1,1)!="\\"){ depthQ = 1 - depthQ }
    if(depthQ) continue
    if(c=="{") depthB++
    else if(c=="}") depthB--
    else if(c=="(") depthP++
    else if(c==")") depthP--
    else if(c=="[") depthS++
    else if(c=="]") depthS--
    else if(c=="," && depthB==0 && depthP==0 && depthS==0){
      if(pos1==0) pos1=i
      else if(pos2==0) pos2=i
      else if(pos3==0){ pos3=i; break }
    }
  }
  if(pos1==0 || pos2==0 || pos3==0) return 0
  f1 = trim(substr(inner, 1, pos1-1))
  f2 = trim(substr(inner, pos1+1, pos2-pos1-1))
  f3 = trim(substr(inner, pos2+1, pos3-pos2-1))
  f4 = trim(substr(inner, pos3+1))
  # remove trailing comma at end if any
  sub(/,[ \t]*$/,"",f4)
  fields1=f1; fields2=f2; fields3=f3; fields4=f4
  return 1
}

BEGIN{
  print ""
  print BOLD "dwm Keybindings" RESET
  print DIM "Source:" RESET " " SRC
  print ""
}

# detect keys[] start/end
/^[[:space:]]*static[[:space:]]+(const[[:space:]]+)?Key[[:space:]]+keys[[:space:]]*\[[^]]*\][[:space:]]*=/ { inblock=1; next }
inblock && /^\};[[:space:]]*$/ { inblock=0; next }

# inside keys[]: parse lines
inblock {
  raw = $0
  line = strip_comments(raw)
  gsub(/,[ \t]*\.\.\.[ \t]*/, ",", line)
  if (line ~ /^[ \t]*$/) next

  # Expand TAGKEYS
  if (line ~ /TAGKEYS\(/) {
    sym = line; sub(/.*TAGKEYS\(\s*/, "", sym); sub(/\s*,.*/, "", sym)
    tagidx = line; sub(/.*TAGKEYS\(\s*XK_[^,]+,\s*/, "", tagidx); sub(/\s*\).*/, "", tagidx)
    keyname = pretty_key(sym)
    tagnum = tagidx + 1
    mods = "MODKEY"
    if (line ~ /^[ \t]*\{[ \t]*[^,]+,[ \t]*TAGKEYS/) {
      mods = line
      sub(/^[ \t]*\{\s*/, "", mods); sub(/\s*,\s*TAGKEYS.*/, "", mods)
    }
    append_row(category_of("view","view"),       pretty_mod(mods),                      keyname, "view",       "tag " tagnum, NR)
    append_row(category_of("toggleview",""),     pretty_mod(mods " | ControlMask"),     keyname, "toggleview", "tag " tagnum, NR)
    append_row(category_of("tag",""),            pretty_mod(mods " | ShiftMask"),       keyname, "tag",        "move to " tagnum, NR)
    append_row(category_of("toggletag",""),      pretty_mod(mods " | ControlMask | ShiftMask"), keyname, "toggletag",  "add/remove " tagnum, NR)
    next
  }

  # Normal rows with outer { ... }
  if (line ~ /^[ \t]*\{/) {
    inner = extract_inner(line)
    if (inner == "") next

    ok = split_fields(inner)
    if (!ok) next

    mods_raw = fields1
    key_raw  = fields2
    fn       = fields3
    arg      = fields4

    keyname = key_raw
    if (key_raw ~ /^XK_/) keyname = pretty_key(key_raw)

    append_row(category_of(fn, fn), pretty_mod(mods_raw), keyname, fn, arg, NR)
    next
  }
}

END{
  cats[1]="Launchers"; cats[2]="Layout"; cats[3]="Tags"; cats[4]="Focus & Stack"
  cats[5]="Monitors";  cats[6]="Scratchpads"; cats[7]="System"; cats[8]="Misc"

  for(i=1;i<=8;i++){
    c=cats[i]
    if(counts[c] > 0){
      print ""
      print BOLD c RESET
      border(); header(); border()
      printf "%s", store[c]
      border()
    }
  }
  print ""
}
# ================= END AWK ==========================
AWK

# Run it
gawk -v MODKEY_DEF="$MODKEY_DEF" -v BOLD="$BOLD" -v DIM="$DIM" -v RESET="$RESET" -v SRC="$CONFIG" -f "$awkfile" "$CONFIG"
