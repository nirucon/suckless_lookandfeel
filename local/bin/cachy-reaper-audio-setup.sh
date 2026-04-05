#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# NIRUCON Pro Audio Bootstrap for CachyOS / Arch Linux
# ============================================================
#
# Purpose:
#   Prepare a stable PipeWire + JACK + REAPER setup suitable
#   for KDE and/or dwm on CachyOS / Arch Linux.
#
# What it does:
#   - Installs required audio packages
#   - Uses paru for package installation
#   - Installs REAPER
#   - Ensures PipeWire + WirePlumber + PipeWire JACK are active
#   - Installs qpwgraph
#   - Installs realtime-privileges
#   - Adds the current user to the realtime group
#   - Writes a low-latency PipeWire config
#   - Disables snd_usb_audio autosuspend
#   - Optionally enables cpupower and sets governor to performance
#   - Creates a pw-jack REAPER launcher
#   - Verifies key parts of the setup
#
# Notes:
#   - Safe to run multiple times
#   - Output is intentionally verbose
#   - Designed to coexist with KDE and dwm
#
# ============================================================

SCRIPT_NAME="$(basename "$0")"
LOG_FILE="${HOME}/pro-audio-setup.log"

# User-level files
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
REAPER_WRAPPER="${BIN_DIR}/reaper-proaudio"
REAPER_DESKTOP="${APP_DIR}/reaper-proaudio.desktop"

PIPEWIRE_CONF_DIR="${HOME}/.config/pipewire/pipewire.conf.d"
PIPEWIRE_LOWLATENCY_CONF="${PIPEWIRE_CONF_DIR}/10-low-latency.conf"

# System-level files
USB_AUDIO_CONF="/etc/modprobe.d/99-snd-usb-audio-noautosuspend.conf"

# Packages
CORE_PACKAGES=(
  pipewire
  wireplumber
  pipewire-pulse
  pipewire-alsa
  pipewire-jack
  qpwgraph
  realtime-privileges
  rtkit
  reaper
)

OPTIONAL_PACKAGES=(
  cpupower
)

# ============================================================
# Logging and helpers
# ============================================================

timestamp() {
  date '+%F %T'
}

log() {
  echo "[$(timestamp)] $*" | tee -a "$LOG_FILE"
}

warn() {
  echo "[$(timestamp)] WARNING: $*" | tee -a "$LOG_FILE" >&2
}

error() {
  echo "[$(timestamp)] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

die() {
  error "$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

backup_file() {
  local file="$1"
  if [[ -e "$file" ]]; then
    local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$file" "$backup"
    log "Created backup: $backup"
  fi
}

confirm() {
  local prompt="${1:-Continue? [y/N]: }"
  local reply
  read -r -p "$prompt" reply || true
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

cleanup_on_error() {
  error "The script aborted unexpectedly. Check the log at: $LOG_FILE"
}
trap cleanup_on_error ERR

# ============================================================
# Sanity checks
# ============================================================

check_environment() {
  : > "$LOG_FILE"

  log "Starting ${SCRIPT_NAME}"
  log "User: ${USER}"
  log "Kernel: $(uname -r)"
  log "Host: $(hostname)"

  [[ $EUID -ne 0 ]] || die "Do not run this script as root. Run it as your normal user with sudo rights."

  command_exists sudo || die "sudo is required."
  command_exists systemctl || die "systemctl is required."
  command_exists pacman || die "pacman is required."
  command_exists id || die "id is required."

  if ! command_exists paru; then
    die "paru is required because you asked for a paru-based install flow."
  fi

  if ! sudo -v; then
    die "sudo authentication failed."
  fi

  log "Environment checks passed."
}

# ============================================================
# Package logic
# ============================================================

show_conflicts_info() {
  log "Checking JACK replacement status..."

  local jack_pkg=""
  local jack2_pkg=""
  local pipewire_jack_pkg=""

  if pacman -Q jack >/dev/null 2>&1; then
    jack_pkg="yes"
  else
    jack_pkg="no"
  fi

  if pacman -Q jack2 >/dev/null 2>&1; then
    jack2_pkg="yes"
  else
    jack2_pkg="no"
  fi

  if pacman -Q pipewire-jack >/dev/null 2>&1; then
    pipewire_jack_pkg="yes"
  else
    pipewire_jack_pkg="no"
  fi

  log "Installed package state:"
  log "  jack: ${jack_pkg}"
  log "  jack2: ${jack2_pkg}"
  log "  pipewire-jack: ${pipewire_jack_pkg}"
  log "If jack or jack2 are present, paru/pacman may ask to replace them with pipewire-jack."
}

install_core_packages() {
  log "Installing core audio packages with paru..."
  show_conflicts_info

  # paru will handle repo packages and conflict prompts more gracefully than
  # our previous brittle manual removal logic.
  paru -S --needed "${CORE_PACKAGES[@]}"

  log "Core package installation completed."
}

install_optional_packages() {
  log "Installing optional packages..."
  paru -S --needed "${OPTIONAL_PACKAGES[@]}" || warn "Optional package installation had minor issues. Continuing."
  log "Optional package installation completed."
}

# ============================================================
# User/group setup
# ============================================================

ensure_realtime_group_membership() {
  if id -nG "$USER" | grep -qw realtime; then
    log "User '${USER}' is already a member of the realtime group."
  else
    log "Adding user '${USER}' to the realtime group..."
    sudo usermod -aG realtime "$USER"
    log "User added to realtime group."
    log "You will need to log out and back in for group membership to fully apply."
  fi
}

# ============================================================
# PipeWire configuration
# ============================================================

write_pipewire_low_latency_config() {
  mkdir -p "$PIPEWIRE_CONF_DIR"

  if [[ -f "$PIPEWIRE_LOWLATENCY_CONF" ]]; then
    backup_file "$PIPEWIRE_LOWLATENCY_CONF"
  fi

  cat > "$PIPEWIRE_LOWLATENCY_CONF" <<'EOF'
context.properties = {
    default.clock.rate          = 48000
    default.clock.allowed-rates = [ 44100 48000 ]
    default.clock.quantum       = 128
    default.clock.min-quantum   = 64
    default.clock.max-quantum   = 256
}
EOF

  log "Wrote PipeWire low-latency configuration:"
  log "  ${PIPEWIRE_LOWLATENCY_CONF}"
}

# ============================================================
# USB audio tuning
# ============================================================

disable_usb_audio_autosuspend() {
  log "Disabling snd_usb_audio autosuspend..."

  if [[ -f "$USB_AUDIO_CONF" ]]; then
    backup_file "$USB_AUDIO_CONF"
  fi

  echo 'options snd_usb_audio autosuspend=0' | sudo tee "$USB_AUDIO_CONF" >/dev/null

  log "Wrote:"
  log "  ${USB_AUDIO_CONF}"
}

# ============================================================
# CPU governor tuning
# ============================================================

configure_cpupower() {
  if ! pacman -Q cpupower >/dev/null 2>&1; then
    warn "cpupower is not installed. Skipping CPU governor setup."
    return
  fi

  log "Enabling cpupower service..."
  sudo systemctl enable --now cpupower.service || warn "Could not enable/start cpupower.service automatically."

  if command_exists cpupower; then
    if sudo cpupower frequency-set -g performance; then
      log "CPU governor set to: performance"
    else
      warn "Could not set CPU governor to performance automatically."
    fi
  else
    warn "cpupower command not found even though package appears installed."
  fi
}

# ============================================================
# REAPER launcher
# ============================================================

create_reaper_wrapper() {
  mkdir -p "$BIN_DIR"

  cat > "$REAPER_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-128/48000}"
exec pw-jack reaper "$@"
EOF

  chmod +x "$REAPER_WRAPPER"

  log "Created REAPER wrapper:"
  log "  ${REAPER_WRAPPER}"
}

create_reaper_desktop_file() {
  mkdir -p "$APP_DIR"

  cat > "$REAPER_DESKTOP" <<EOF
[Desktop Entry]
Name=REAPER Pro Audio
Comment=Launch REAPER through PipeWire JACK
Exec=${REAPER_WRAPPER}
Icon=reaper
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Recorder;
StartupNotify=true
EOF

  log "Created desktop entry:"
  log "  ${REAPER_DESKTOP}"
}

# ============================================================
# Services
# ============================================================

enable_and_restart_user_services() {
  log "Reloading user systemd daemon..."
  systemctl --user daemon-reload

  log "Enabling user services..."
  systemctl --user enable pipewire.service pipewire-pulse.service wireplumber.service

  log "Restarting user audio services..."
  systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service

  log "User audio services are enabled and restarted."
}

# ============================================================
# Verification
# ============================================================

check_pipewire() {
  log "Checking PulseAudio compatibility layer through pactl..."
  if command_exists pactl; then
    pactl info | tee -a "$LOG_FILE" >/dev/null
    log "pactl check completed."
  else
    warn "pactl not found."
  fi
}

check_alsa_cards() {
  log "Checking ALSA devices..."
  if command_exists aplay; then
    aplay -l | tee -a "$LOG_FILE" >/dev/null || true
    log "ALSA check completed."
  else
    warn "aplay not found."
  fi
}

check_umc1820() {
  log "Checking whether a BEHRINGER UMC1820-style device is visible..."

  local found="no"

  if command_exists aplay; then
    if aplay -l 2>/dev/null | grep -Ei 'behringer|umc1820' >/dev/null; then
      found="yes"
    fi
  fi

  if [[ "$found" == "yes" ]]; then
    log "A matching BEHRINGER / UMC1820 device appears to be present."
  else
    warn "No BEHRINGER / UMC1820 device was detected in 'aplay -l'."
    warn "If the interface is powered on and connected, re-check after logout/login or reboot."
  fi
}

check_reaper_binary() {
  log "Checking REAPER binary..."
  if command_exists reaper; then
    log "REAPER is available at: $(command -v reaper)"
  else
    warn "REAPER binary was not found in PATH."
  fi
}

check_qpwgraph_binary() {
  log "Checking qpwgraph binary..."
  if command_exists qpwgraph; then
    log "qpwgraph is available at: $(command -v qpwgraph)"
  else
    warn "qpwgraph binary was not found in PATH."
  fi
}

print_summary() {
  cat <<'EOF'

============================================================
SETUP COMPLETE
============================================================

Recommended next steps:

1. Log out and log back in
   This is important if your user was just added to the realtime group.

2. Start REAPER using:
   reaper-proaudio

   or from your application menu:
   REAPER Pro Audio

3. In REAPER:
   Options > Preferences > Audio > Device

   Set:
   Audio system: JACK

4. Start qpwgraph:
   qpwgraph

   Use it to verify that all inputs and outputs from your interface
   are visible and correctly routed.

5. Suggested baseline values in REAPER:
   Sample rate: 48000
   Block size / buffer: 128 or 256

6. If multichannel still does not appear in REAPER:
   - fully close REAPER
   - launch it again using reaper-proaudio
   - re-check qpwgraph
   - confirm your interface is visible in:
     aplay -l
     pactl info

Important:
- This setup is designed to work with both KDE and dwm.
- It does not depend on Plasma-specific audio tools.
- It uses PipeWire system-wide with PipeWire JACK for REAPER.

EOF
}

# ============================================================
# Main
# ============================================================

main() {
  check_environment
  install_core_packages
  install_optional_packages
  ensure_realtime_group_membership
  write_pipewire_low_latency_config
  disable_usb_audio_autosuspend
  configure_cpupower
  create_reaper_wrapper
  create_reaper_desktop_file
  enable_and_restart_user_services
  check_pipewire
  check_alsa_cards
  check_umc1820
  check_reaper_binary
  check_qpwgraph_binary
  print_summary

  log "All tasks completed successfully."
}

main "$@"
