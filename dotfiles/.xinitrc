#!/bin/sh
# =============================================================================
#  .xinitrc — Arch Linux + Suckless setup
#  Created by install_suckless.sh
#  
#  This file is created ONCE and never modified by install scripts.
#  Autostart programs are managed via hooks in ~/.config/xinitrc.d/
# =============================================================================

# ───────── 1) Session Setup ─────────

# Always start in $HOME
cd "$HOME"

# Start D-Bus session if not already running
# This ensures GUI apps can communicate (notifications, file dialogs, etc.)
if [ -z "${DBUS_SESSION_BUS_ADDRESS-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session "$0" "$@"
fi

# Export X environment to systemd user services
# Allows user services (like dunst.service) to access DISPLAY and XAUTHORITY
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
fi

# Load X resources (fonts, colors, DPI settings)
[ -r "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Set keyboard layout (change 'se' to your layout: us, gb, de, etc.)
command -v setxkbmap >/dev/null 2>&1 && setxkbmap se

# Set root window background color (prevents ugly gray)
command -v xsetroot >/dev/null 2>&1 && xsetroot -solid "#111111"

# Optional: enable NumLock at startup
# command -v numlockx >/dev/null 2>&1 && numlockx on

# Optional: HiDPI scaling (uncomment and adjust for your display)
# command -v xrandr >/dev/null 2>&1 && xrandr --output eDP-1 --scale 0.75x0.75

# ───────── 2) GTK & Qt Theming ─────────

export XDG_CONFIG_HOME="$HOME/.config"
export GTK_THEME="Adwaita:dark"
export QT_STYLE_OVERRIDE="kvantum"
export QT_QPA_PLATFORMTHEME="qt5ct"
export XCURSOR_THEME="Adwaita"
export GTK2_RC_FILES="$HOME/.gtkrc-2.0"

# ───────── 3) Autostart Programs (via hooks) ─────────

# Source all executable hooks from ~/.config/xinitrc.d/
# Other install scripts (lookandfeel, statusbar) create hooks here
# Hooks are executed in alphabetical order (10-*, 20-*, 30-*, etc.)
if [ -d "$HOME/.config/xinitrc.d" ]; then
  for hook in "$HOME/.config/xinitrc.d"/*.sh; do
    [ -x "$hook" ] && . "$hook"
  done
fi

# ───────── 4) DWM Launch & Cleanup ─────────

# Ensure all background processes terminate when X session ends
trap 'kill -- -$$' EXIT

# DWM restart loop
# If DWM crashes or you reload config (Mod+Shift+Q), it restarts automatically
# Exit loop by logging out (Mod+Shift+E) or closing X server
while true; do
  /usr/local/bin/dwm 2>/tmp/dwm.log
done
