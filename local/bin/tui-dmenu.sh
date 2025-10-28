#!/usr/bin/env bash
# tui-dmenu.sh — create and launch TUI apps via dmenu
# Place in ~/.local/bin and run: chmod +x ~/.local/bin/tui-dmenu.sh
# You can create persistent shortcuts (wrapper scripts) stored in ~/.local/bin.
# Generated shortcuts are marked with: '# TUI-DMENU SHORTCUT' and can be safely deleted.
# They are named 'tui-<slug>' to avoid collisions.

set -euo pipefail

DMENU_BIN="${DMENU_BIN:-dmenu}"
DMENU_OPTS=${DMENU_OPTS:-"-i -l 12"}
INSTALL_DIR="$HOME/.local/bin"
MARKER="# TUI-DMENU SHORTCUT"

# ---------------- Terminal detection (st → alacritty → others) ----------------
detect_terminal() {
  if [[ -n "${TERMINAL:-}" ]]; then
    case "$TERMINAL" in
    *st*) echo "st -e" && return ;;
    *alacritty*) echo "alacritty -e" && return ;;
    *kitty*) echo "kitty -e" && return ;;
    *foot*) echo "foot -e" && return ;;
    *wezterm*) echo "wezterm start --" && return ;;
    *gnome-terminal*) echo "gnome-terminal --" && return ;;
    *konsole*) echo "konsole -e" && return ;;
    *xfce4-terminal*) echo "xfce4-terminal -e" && return ;;
    *xterm*) echo "xterm -e" && return ;;
    esac
  fi

  if command -v st >/dev/null 2>&1; then
    echo "st -e"
  elif command -v alacritty >/dev/null 2>&1; then
    echo "alacritty -e"
  elif command -v kitty >/dev/null 2>&1; then
    echo "kitty -e"
  elif command -v foot >/dev/null 2>&1; then
    echo "foot -e"
  elif command -v wezterm >/dev/null 2>&1; then
    echo "wezterm start --"
  elif command -v gnome-terminal >/dev/null 2>&1; then
    echo "gnome-terminal --"
  elif command -v konsole >/dev/null 2>&1; then
    echo "konsole -e"
  elif command -v xfce4-terminal >/dev/null 2>&1; then
    echo "xfce4-terminal -e"
  elif command -v xterm >/dev/null 2>&1; then
    echo "xterm -e"
  else
    echo ""
  fi
}

launch_in_terminal() {
  local cmd="$1"
  local term_runner
  term_runner="$(detect_terminal)"
  if [[ -z "$term_runner" ]]; then
    notify-send "tui-dmenu" "No terminal emulator found." 2>/dev/null || true
    echo "Error: No terminal found. Install st, alacritty, or another terminal." >&2
    exit 1
  fi
  eval "$term_runner $cmd" &
  disown
}

# ------------------------- Predefined TUI items -------------------------------
# fastfetch wrapped so terminal stays open
default_items() {
  cat <<'EOF'
btop - system monitor | btop
fastfetch - system info | sh -c 'fastfetch; echo; read -n 1 -p "Press any key to close..."'
yazi - file manager | yazi
nvim - text editor | nvim
nano - text editor | nano
cmus - music player | cmus
EOF
}

# --------------------------- Utility helpers ---------------------------------
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\+/-/g; s/^-//; s/-$//'
}

list_installed_shortcuts() {
  [[ ! -d "$INSTALL_DIR" ]] && return
  local f label cmd
  while IFS= read -r -d '' f; do
    label="$(grep -m1 '^# LABEL:' "$f" | sed 's/^# LABEL:[[:space:]]*//')"
    cmd="$(grep -m1 '^# CMD:' "$f" | sed 's/^# CMD:[[:space:]]*//')"
    [[ -z "$label" ]] && label="$(basename "$f")"
    [[ -z "$cmd" ]] && cmd="(unknown)"
    printf '%s | %s | %s\n' "$label" "$cmd" "$(basename "$f")"
  done < <(grep -Z -l -- "$MARKER" "$INSTALL_DIR"/* 2>/dev/null || true)
}

create_shortcut_file() {
  local label="$1"
  local command="$2"
  local filename="$3"
  mkdir -p "$INSTALL_DIR"
  local dest="$INSTALL_DIR/$filename"
  cat >"$dest" <<EOF
#!/usr/bin/env bash
$MARKER
# LABEL: $label
# CMD: $command
set -euo pipefail

detect_terminal() {
  if [[ -n "\${TERMINAL:-}" ]]; then
    case "\$TERMINAL" in
      *st*) echo "st -e" && return ;;
      *alacritty*) echo "alacritty -e" && return ;;
      *kitty*) echo "kitty -e" && return ;;
      *foot*) echo "foot -e" && return ;;
      *wezterm*) echo "wezterm start --" && return ;;
      *gnome-terminal*) echo "gnome-terminal --" && return ;;
      *konsole*) echo "konsole -e" && return ;;
      *xfce4-terminal*) echo "xfce4-terminal -e" && return ;;
      *xterm*) echo "xterm -e" && return ;;
    esac
  fi
  if command -v st >/dev/null 2>&1; then echo "st -e"
  elif command -v alacritty >/dev/null 2>&1; then echo "alacritty -e"
  elif command -v kitty >/dev/null 2>&1; then echo "kitty -e"
  elif command -v foot >/dev/null 2>&1; then echo "foot -e"
  elif command -v wezterm >/dev/null 2>&1; then echo "wezterm start --"
  elif command -v gnome-terminal >/dev/null 2>&1; then echo "gnome-terminal --"
  elif command -v konsole >/dev/null 2>&1; then echo "konsole -e"
  elif command -v xfce4-terminal >/dev/null 2>&1; then echo "xfce4-terminal -e"
  elif command -v xterm >/dev/null 2>&1; then echo "xterm -e"
  else echo ""; fi
}

runner="\$(detect_terminal)"
[[ -z "\$runner" ]] && { echo "Error: No terminal found."; exit 1; }
exec \$runner $command
EOF
  chmod +x "$dest"
}

delete_shortcut() {
  local filename="$1"
  local full="$INSTALL_DIR/$filename"
  [[ -f "$full" ]] && rm -f "$full" && notify-send "tui-dmenu" "Deleted: $filename" 2>/dev/null || true
}

# ------------------------------ Actions --------------------------------------
action_launch_installed() {
  local line cmd
  line="$(list_installed_shortcuts | ${DMENU_BIN} ${DMENU_OPTS} -p 'Installed (Label | cmd | file)')"
  [[ -z "$line" ]] && exit 0
  cmd="$(echo "$line" | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//')"
  launch_in_terminal "$cmd"
}

action_launch_predefined() {
  local sel cmd
  sel="$(default_items | ${DMENU_BIN} ${DMENU_OPTS} -p 'Predefined (Label | command)')"
  [[ -z "$sel" ]] && exit 0
  cmd="$(echo "$sel" | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//')"
  launch_in_terminal "$cmd"
}

action_create_new() {
  local label cmd filename
  label="$(printf '' | ${DMENU_BIN} ${DMENU_OPTS} -p 'Shortcut label')"
  [[ -z "$label" ]] && exit 0
  cmd="$(printf '' | ${DMENU_BIN} ${DMENU_OPTS} -p 'Command to run')"
  [[ -z "$cmd" ]] && exit 0
  filename="tui-$(slugify "$label")"
  create_shortcut_file "$label" "$cmd" "$filename"
  notify-send "tui-dmenu" "Created: $filename" 2>/dev/null || true
}

action_install_preset_pack() {
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local label cmd filename
    label="$(echo "$line" | awk -F'|' '{print $1}' | sed 's/[[:space:]]*$//')"
    cmd="$(echo "$line" | awk -F'|' '{print $2}' | sed 's/^ *//')"
    filename="tui-$(slugify "$label")"
    create_shortcut_file "$label" "$cmd" "$filename"
  done < <(default_items)
  notify-send "tui-dmenu" "Preset pack installed." 2>/dev/null || true
}

action_delete_shortcut() {
  local line filename
  line="$(list_installed_shortcuts | ${DMENU_BIN} ${DMENU_OPTS} -p 'Delete which?')"
  [[ -z "$line" ]] && exit 0
  filename="$(echo "$line" | awk -F'|' '{print $3}' | sed 's/^ *//;s/ *$//')"
  delete_shortcut "$filename"
}

# -------------------------------- Main menu ----------------------------------
main_menu() {
  local choice
  choice="$(printf '%s\n' \
    "Launch installed shortcut" \
    "Launch predefined (quick run)" \
    "Create new TUI shortcut" \
    "Install preset pack" \
    "Delete a shortcut" |
    ${DMENU_BIN} ${DMENU_OPTS} -p 'tui-dmenu')"
  case "${choice:-}" in
  "Launch installed shortcut") action_launch_installed ;;
  "Launch predefined (quick run)") action_launch_predefined ;;
  "Create new TUI shortcut") action_create_new ;;
  "Install preset pack") action_install_preset_pack ;;
  "Delete a shortcut") action_delete_shortcut ;;
  *) exit 0 ;;
  esac
}

main_menu
