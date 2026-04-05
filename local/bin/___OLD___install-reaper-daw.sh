#!/bin/bash

################################################################################
# Reaper Audio Workstation Setup Script for Arch Linux
#
# Description: Comprehensive installation script for Reaper DAW with complete
#              audio production environment setup including realtime optimization,
#              VST support, synthesizers, effects, and drum machines.
#
# Requirements: Arch Linux, dwm, PipeWire, internet connection
# Author: Audio Production Setup Script
# License: MIT
################################################################################

set -euo pipefail

################################################################################
# GLOBAL VARIABLES AND COLORS
################################################################################

readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="/tmp/reaper-setup-$(date +%Y%m%d-%H%M%S).log"
readonly BACKUP_DIR="$HOME/.config/reaper-setup-backup-$(date +%Y%m%d-%H%M%S)"

# Color definitions for beautiful terminal output
readonly COLOR_RESET='\033[0m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'

# Unicode symbols for enhanced UI
readonly SYMBOL_CHECK="✓"
readonly SYMBOL_CROSS="✗"
readonly SYMBOL_ARROW="→"
readonly SYMBOL_STAR="★"
readonly SYMBOL_MUSIC="♪"

# Installation selections (will be populated by user choices)
declare -A SELECTIONS=(
  [MODE]="install"
  [KERNEL_CHOICE]=""
  [YABRIDGE]=false
  [VITAL]=false
  [SURGE]=false
  [DEXED]=false
  [HELM]=false
  [ODIN2]=false
  [ZYN]=false
  [DRAGONFLY]=false
  [LSP]=false
  [X42]=false
  [CALF]=false
  [HYDROGEN]=false
  [DRUMGIZMO]=false
  [DRUMKV1]=false
  [CARLA]=false
  [GUITARIX]=false
  [SFIZZ]=false
  [QJACKCTL]=false
)

################################################################################
# LOGGING AND ERROR HANDLING
################################################################################

# Initialize log file
init_logging() {
  touch "$LOG_FILE"
  echo "=== Reaper Audio Setup Log - $(date) ===" >>"$LOG_FILE"
  log_info "Log file created: $LOG_FILE"
}

# Log messages with timestamp
log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >>"$LOG_FILE"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >>"$LOG_FILE"
}

log_success() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*" >>"$LOG_FILE"
}

# Error handler
error_exit() {
  echo -e "\n${COLOR_RED}${COLOR_BOLD}${SYMBOL_CROSS} ERROR:${COLOR_RESET} $1" >&2
  log_error "$1"
  echo -e "${COLOR_YELLOW}Check log file: ${COLOR_CYAN}$LOG_FILE${COLOR_RESET}"
  exit 1
}

# Cleanup on exit
cleanup() {
  if [[ $? -ne 0 ]]; then
    echo -e "\n${COLOR_YELLOW}Installation interrupted. Log saved to: ${COLOR_CYAN}$LOG_FILE${COLOR_RESET}"
  fi
}

trap cleanup EXIT

################################################################################
# UI HELPER FUNCTIONS
################################################################################

# Print a beautiful header
print_header() {
  clear
  echo -e "${COLOR_CYAN}${COLOR_BOLD}"
  echo "╔════════════════════════════════════════════════════════════════════════╗"
  echo "║                                                                        ║"
  echo "║          ${SYMBOL_MUSIC}  REAPER AUDIO WORKSTATION SETUP  ${SYMBOL_MUSIC}                      ║"
  echo "║                                                                        ║"
  echo "║                    Professional Audio Production                      ║"
  echo "║                    for Arch Linux + PipeWire                          ║"
  echo "║                                                                        ║"
  echo "╚════════════════════════════════════════════════════════════════════════╝"
  echo -e "${COLOR_RESET}"
  echo -e "${COLOR_WHITE}Version: ${COLOR_CYAN}$SCRIPT_VERSION${COLOR_RESET}"
  echo ""
}

# Print section header
print_section() {
  echo ""
  echo -e "${COLOR_MAGENTA}${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo -e "${COLOR_MAGENTA}${COLOR_BOLD}${SYMBOL_ARROW} $1${COLOR_RESET}"
  echo -e "${COLOR_MAGENTA}${COLOR_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo ""
}

# Print success message
print_success() {
  echo -e "${COLOR_GREEN}${COLOR_BOLD}${SYMBOL_CHECK} $1${COLOR_RESET}"
  log_success "$1"
}

# Print info message
print_info() {
  echo -e "${COLOR_BLUE}${SYMBOL_ARROW} $1${COLOR_RESET}"
  log_info "$1"
}

# Print warning message
print_warning() {
  echo -e "${COLOR_YELLOW}⚠ $1${COLOR_RESET}"
}

# Progress indicator with spinner
show_progress() {
  local pid=$1
  local message=$2
  local spin='-\|/'
  local i=0

  echo -n "  "
  while kill -0 "$pid" 2>/dev/null; do
    i=$(((i + 1) % 4))
    printf "\r${COLOR_CYAN}${spin:$i:1}${COLOR_RESET} ${message}"
    sleep 0.1
  done
  printf "\r${COLOR_GREEN}${SYMBOL_CHECK}${COLOR_RESET} ${message}\n"
}

# Press any key to continue
press_any_key() {
  echo ""
  echo -e "${COLOR_YELLOW}Press any key to continue...${COLOR_RESET}"
  read -n 1 -s -r
}

################################################################################
# SYSTEM CHECK FUNCTIONS
################################################################################

# Check if running on Arch Linux
check_arch_linux() {
  if [[ ! -f /etc/arch-release ]]; then
    error_exit "This script is designed for Arch Linux only"
  fi
  print_success "Running on Arch Linux"
}

# Check if running as root (should not be)
check_not_root() {
  if [[ $EUID -eq 0 ]]; then
    error_exit "Do not run this script as root. Run as regular user with sudo privileges."
  fi
  print_success "Running as non-root user: $USER"
}

# Check for sudo privileges
check_sudo() {
  if ! sudo -n true 2>/dev/null; then
    print_info "This script requires sudo privileges. You may be prompted for your password."
    sudo -v || error_exit "Failed to obtain sudo privileges"
  fi
  print_success "Sudo privileges confirmed"
}

# Check for internet connection
check_internet() {
  if ! ping -c 1 archlinux.org &>/dev/null; then
    error_exit "No internet connection detected. Please connect to the internet and try again."
  fi
  print_success "Internet connection verified"
}

# Check and install yay if needed
check_yay() {
  if ! command -v yay &>/dev/null; then
    print_warning "yay AUR helper not found. Installing yay..."

    sudo pacman -S --needed --noconfirm base-devel git || error_exit "Failed to install base-devel and git"

    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || error_exit "Failed to create temporary directory"

    git clone https://aur.archlinux.org/yay.git || error_exit "Failed to clone yay repository"
    cd yay || error_exit "Failed to enter yay directory"
    makepkg -si --noconfirm || error_exit "Failed to build and install yay"

    cd "$HOME" || exit
    rm -rf "$temp_dir"

    print_success "yay installed successfully"
  else
    print_success "yay AUR helper found"
  fi
}

# Check PipeWire installation
check_pipewire() {
  if ! command -v pipewire &>/dev/null; then
    error_exit "PipeWire not found. Please install PipeWire before running this script."
  fi
  print_success "PipeWire detected"
}

################################################################################
# INTERACTIVE MENU FUNCTIONS
################################################################################

# Mode selection menu (install or uninstall)
select_mode() {
  print_section "SELECT MODE"

  echo "What would you like to do?"
  echo ""
  echo -e "  ${COLOR_CYAN}1)${COLOR_RESET} Install Reaper and audio production environment"
  echo -e "  ${COLOR_CYAN}2)${COLOR_RESET} Uninstall all packages installed by this script ${COLOR_RED}(except kernels)${COLOR_RESET}"
  echo ""

  while true; do
    read -p "Enter choice [1-2]: " choice
    case $choice in
    1)
      SELECTIONS[MODE]="install"
      print_info "Installation mode selected"
      break
      ;;
    2)
      SELECTIONS[MODE]="uninstall"
      print_info "Uninstall mode selected"
      break
      ;;
    *)
      echo -e "${COLOR_RED}Invalid choice. Please enter 1 or 2.${COLOR_RESET}"
      ;;
    esac
  done

  press_any_key
}

# Kernel selection menu
select_kernel() {
  print_section "KERNEL SELECTION"

  echo "Select audio-optimized kernel (optional but recommended):"
  echo ""
  echo -e "  ${COLOR_CYAN}1)${COLOR_RESET} Keep current kernel ($(uname -r))"
  echo -e "  ${COLOR_CYAN}2)${COLOR_RESET} linux-zen      ${COLOR_GREEN}[Recommended]${COLOR_RESET} - Optimized for desktop/audio with better scheduling"
  echo -e "  ${COLOR_CYAN}3)${COLOR_RESET} linux-rt       ${COLOR_YELLOW}[Advanced]${COLOR_RESET}    - Real-time kernel for ultra-low latency (may affect system stability)"
  echo ""
  echo -e "${COLOR_YELLOW}Note: Choosing a new kernel will require a reboot after installation${COLOR_RESET}"
  echo ""

  while true; do
    read -p "Enter choice [1-3]: " choice
    case $choice in
    1)
      SELECTIONS[KERNEL_CHOICE]="current"
      print_info "Keeping current kernel"
      break
      ;;
    2)
      SELECTIONS[KERNEL_CHOICE]="zen"
      print_info "Will install linux-zen kernel"
      break
      ;;
    3)
      SELECTIONS[KERNEL_CHOICE]="rt"
      print_info "Will install linux-rt kernel"
      break
      ;;
    *)
      echo -e "${COLOR_RED}Invalid choice. Please enter 1, 2, or 3.${COLOR_RESET}"
      ;;
    esac
  done

  press_any_key
}

# Windows VST support menu
select_yabridge() {
  print_section "WINDOWS VST SUPPORT"

  echo "Would you like to install yabridge for Windows VST plugin support?"
  echo ""
  echo -e "${COLOR_WHITE}What is yabridge?${COLOR_RESET}"
  echo "  - Enables running Windows VST2/VST3 plugins on Linux"
  echo "  - Requires Wine (will be installed automatically)"
  echo "  - Essential if you use commercial Windows plugins"
  echo ""

  read -p "Install yabridge + yabridgectl? [y/N]: " choice
  case $choice in
  [yY] | [yY][eE][sS])
    SELECTIONS[YABRIDGE]=true
    print_info "yabridge support will be installed"
    ;;
  *)
    print_info "Skipping yabridge installation"
    ;;
  esac

  press_any_key
}

# Synthesizer selection menu
select_synthesizers() {
  print_section "NATIVE LINUX SYNTHESIZERS"

  echo "Select synthesizers to install (space to toggle, enter to confirm):"
  echo ""

  local options=(
    "VITAL:Vital VST:Modern wavetable synthesizer - Industry standard [FREE]"
    "SURGE:Surge XT:Powerful open-source hybrid synthesizer"
    "DEXED:Dexed:DX7 FM synthesizer emulator - Classic 80s sounds"
    "HELM:Helm:Polyphonic synthesizer with modern design"
    "ODIN2:Odin 2:Advanced synthesizer with semi-modular architecture"
    "ZYN:ZynAddSubFX:Feature-rich software synthesizer"
  )

  local selected=()

  # Use dialog if available, otherwise fallback to simple selection
  if command -v dialog &>/dev/null; then
    local dialog_options=()
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      dialog_options+=("$key" "$name - $desc" "off")
    done

    local choices=$(dialog --stdout --checklist "Select Synthesizers:" 20 78 10 "${dialog_options[@]}")

    if [[ -n "$choices" ]]; then
      for choice in $choices; do
        choice=$(echo "$choice" | tr -d '"')
        SELECTIONS[$choice]=true
        selected+=("$choice")
      done
    fi
  else
    # Fallback to simple y/n prompts
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      echo -e "${COLOR_CYAN}$name${COLOR_RESET}"
      echo "  $desc"
      read -p "  Install? [y/N]: " choice
      case $choice in
      [yY] | [yY][eE][sS])
        SELECTIONS[$key]=true
        selected+=("$key")
        ;;
      esac
      echo ""
    done
  fi

  if [[ ${#selected[@]} -gt 0 ]]; then
    print_info "Selected synthesizers: ${selected[*]}"
  else
    print_info "No synthesizers selected"
  fi

  press_any_key
}

# Effects selection menu
select_effects() {
  print_section "AUDIO EFFECTS & PLUGINS"

  echo "Select audio effects and plugin suites to install:"
  echo ""

  local options=(
    "DRAGONFLY:Dragonfly Reverb:Professional reverb plugin suite"
    "LSP:LSP Plugins:Comprehensive audio plugin suite (EQ, comp, limiters, etc.)"
    "X42:x42-plugins:Professional mixing and mastering tools"
    "CALF:Calf Studio Gear:Large collection of studio effects"
  )

  local selected=()

  if command -v dialog &>/dev/null; then
    local dialog_options=()
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      dialog_options+=("$key" "$name - $desc" "off")
    done

    local choices=$(dialog --stdout --checklist "Select Audio Effects:" 20 78 10 "${dialog_options[@]}")

    if [[ -n "$choices" ]]; then
      for choice in $choices; do
        choice=$(echo "$choice" | tr -d '"')
        SELECTIONS[$choice]=true
        selected+=("$choice")
      done
    fi
  else
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      echo -e "${COLOR_CYAN}$name${COLOR_RESET}"
      echo "  $desc"
      read -p "  Install? [y/N]: " choice
      case $choice in
      [yY] | [yY][eE][sS])
        SELECTIONS[$key]=true
        selected+=("$key")
        ;;
      esac
      echo ""
    done
  fi

  if [[ ${#selected[@]} -gt 0 ]]; then
    print_info "Selected effects: ${selected[*]}"
  else
    print_info "No effects selected"
  fi

  press_any_key
}

# Drum machine selection menu
select_drums() {
  print_section "DRUM MACHINES & SAMPLERS"

  echo "Select drum machines and samplers to install:"
  echo ""

  local options=(
    "HYDROGEN:Hydrogen:Advanced drum machine and pattern sequencer"
    "DRUMGIZMO:DrumGizmo:Multichannel drum sampler with realistic kits"
    "DRUMKV1:drumkv1:Simple but powerful drum sampler"
  )

  local selected=()

  if command -v dialog &>/dev/null; then
    local dialog_options=()
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      dialog_options+=("$key" "$name - $desc" "off")
    done

    local choices=$(dialog --stdout --checklist "Select Drum Machines:" 20 78 10 "${dialog_options[@]}")

    if [[ -n "$choices" ]]; then
      for choice in $choices; do
        choice=$(echo "$choice" | tr -d '"')
        SELECTIONS[$choice]=true
        selected+=("$choice")
      done
    fi
  else
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      echo -e "${COLOR_CYAN}$name${COLOR_RESET}"
      echo "  $desc"
      read -p "  Install? [y/N]: " choice
      case $choice in
      [yY] | [yY][eE][sS])
        SELECTIONS[$key]=true
        selected+=("$key")
        ;;
      esac
      echo ""
    done
  fi

  if [[ ${#selected[@]} -gt 0 ]]; then
    print_info "Selected drum machines: ${selected[*]}"
  else
    print_info "No drum machines selected"
  fi

  press_any_key
}

# Extra tools selection menu
select_extras() {
  print_section "ADDITIONAL AUDIO TOOLS"

  echo "Select additional audio production tools:"
  echo ""

  local options=(
    "CARLA:Carla:Plugin host and rack - Essential for complex routing"
    "GUITARIX:Guitarix:Virtual guitar amplifier and effects"
    "SFIZZ:sfizz:SFZ sample player - For orchestral libraries"
    "QJACKCTL:QjackCtl:Advanced JACK audio connection kit control"
  )

  local selected=()

  if command -v dialog &>/dev/null; then
    local dialog_options=()
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      dialog_options+=("$key" "$name - $desc" "off")
    done

    local choices=$(dialog --stdout --checklist "Select Additional Tools:" 20 78 10 "${dialog_options[@]}")

    if [[ -n "$choices" ]]; then
      for choice in $choices; do
        choice=$(echo "$choice" | tr -d '"')
        SELECTIONS[$choice]=true
        selected+=("$choice")
      done
    fi
  else
    for opt in "${options[@]}"; do
      IFS=':' read -r key name desc <<<"$opt"
      echo -e "${COLOR_CYAN}$name${COLOR_RESET}"
      echo "  $desc"
      read -p "  Install? [y/N]: " choice
      case $choice in
      [yY] | [yY][eE][sS])
        SELECTIONS[$key]=true
        selected+=("$key")
        ;;
      esac
      echo ""
    done
  fi

  if [[ ${#selected[@]} -gt 0 ]]; then
    print_info "Selected additional tools: ${selected[*]}"
  else
    print_info "No additional tools selected"
  fi

  press_any_key
}

################################################################################
# INSTALLATION SUMMARY
################################################################################

display_summary() {
  print_section "INSTALLATION SUMMARY"

  echo -e "${COLOR_WHITE}${COLOR_BOLD}The following components will be installed:${COLOR_RESET}"
  echo ""

  echo -e "${COLOR_CYAN}${COLOR_BOLD}[CORE SYSTEM - Always Installed]${COLOR_RESET}"
  echo "  • Realtime privileges and audio group configuration"
  echo "  • PipeWire JACK compatibility layer"
  echo "  • qpwgraph - PipeWire graph manager"
  echo "  • System latency optimizations"
  echo "  • Reaper DAW (latest version)"
  echo "  • SWS Extensions for Reaper"
  echo "  • ReaPack package manager"
  echo ""

  if [[ "${SELECTIONS[KERNEL_CHOICE]}" != "current" ]]; then
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}[KERNEL]${COLOR_RESET}"
    if [[ "${SELECTIONS[KERNEL_CHOICE]}" == "zen" ]]; then
      echo "  • linux-zen (optimized for audio/desktop)"
    elif [[ "${SELECTIONS[KERNEL_CHOICE]}" == "rt" ]]; then
      echo "  • linux-rt (real-time kernel)"
    fi
    echo ""
  fi

  if ${SELECTIONS[YABRIDGE]}; then
    echo -e "${COLOR_MAGENTA}${COLOR_BOLD}[WINDOWS VST SUPPORT]${COLOR_RESET}"
    echo "  • yabridge + yabridge-bin"
    echo "  • yabridgectl"
    echo "  • Wine-staging"
    echo ""
  fi

  # List selected synthesizers
  local synth_list=()
  ${SELECTIONS[VITAL]} && synth_list+=("Vital")
  ${SELECTIONS[SURGE]} && synth_list+=("Surge XT")
  ${SELECTIONS[DEXED]} && synth_list+=("Dexed")
  ${SELECTIONS[HELM]} && synth_list+=("Helm")
  ${SELECTIONS[ODIN2]} && synth_list+=("Odin 2")
  ${SELECTIONS[ZYN]} && synth_list+=("ZynAddSubFX")

  if [[ ${#synth_list[@]} -gt 0 ]]; then
    echo -e "${COLOR_GREEN}${COLOR_BOLD}[SYNTHESIZERS]${COLOR_RESET}"
    for synth in "${synth_list[@]}"; do
      echo "  • $synth"
    done
    echo ""
  fi

  # List selected effects
  local effects_list=()
  ${SELECTIONS[DRAGONFLY]} && effects_list+=("Dragonfly Reverb")
  ${SELECTIONS[LSP]} && effects_list+=("LSP Plugins")
  ${SELECTIONS[X42]} && effects_list+=("x42-plugins")
  ${SELECTIONS[CALF]} && effects_list+=("Calf Studio Gear")

  if [[ ${#effects_list[@]} -gt 0 ]]; then
    echo -e "${COLOR_BLUE}${COLOR_BOLD}[AUDIO EFFECTS]${COLOR_RESET}"
    for effect in "${effects_list[@]}"; do
      echo "  • $effect"
    done
    echo ""
  fi

  # List selected drum machines
  local drums_list=()
  ${SELECTIONS[HYDROGEN]} && drums_list+=("Hydrogen")
  ${SELECTIONS[DRUMGIZMO]} && drums_list+=("DrumGizmo")
  ${SELECTIONS[DRUMKV1]} && drums_list+=("drumkv1")

  if [[ ${#drums_list[@]} -gt 0 ]]; then
    echo -e "${COLOR_RED}${COLOR_BOLD}[DRUM MACHINES]${COLOR_RESET}"
    for drum in "${drums_list[@]}"; do
      echo "  • $drum"
    done
    echo ""
  fi

  # List selected extras
  local extras_list=()
  ${SELECTIONS[CARLA]} && extras_list+=("Carla")
  ${SELECTIONS[GUITARIX]} && extras_list+=("Guitarix")
  ${SELECTIONS[SFIZZ]} && extras_list+=("sfizz")
  ${SELECTIONS[QJACKCTL]} && extras_list+=("QjackCtl")

  if [[ ${#extras_list[@]} -gt 0 ]]; then
    echo -e "${COLOR_CYAN}${COLOR_BOLD}[ADDITIONAL TOOLS]${COLOR_RESET}"
    for extra in "${extras_list[@]}"; do
      echo "  • $extra"
    done
    echo ""
  fi

  echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo ""
  read -p "Proceed with installation? [Y/n]: " confirm
  case $confirm in
  [nN] | [nN][oO])
    echo ""
    print_warning "Installation cancelled by user"
    exit 0
    ;;
  *)
    print_info "Starting installation..."
    ;;
  esac
}

################################################################################
# SYSTEM CONFIGURATION FUNCTIONS
################################################################################

# Configure realtime privileges
configure_realtime() {
  print_info "Configuring realtime audio privileges..."

  # Add user to audio group if not already added
  if ! groups "$USER" | grep -q audio; then
    sudo usermod -aG audio "$USER" || error_exit "Failed to add user to audio group"
    print_success "User $USER added to audio group"
  else
    print_info "User already in audio group"
  fi

  # Configure limits.conf for realtime priority
  local limits_file="/etc/security/limits.d/99-realtime.conf"
  local limits_dir="/etc/security/limits.d"

  # Ensure directory exists
  if [[ ! -d "$limits_dir" ]]; then
    sudo mkdir -p "$limits_dir" || error_exit "Failed to create limits.d directory"
  fi

  if [[ ! -f "$limits_file" ]] || ! grep -q "@audio" "$limits_file" 2>/dev/null; then
    sudo tee "$limits_file" >/dev/null <<EOF
# Realtime audio configuration
@audio   -  rtprio     99
@audio   -  memlock    unlimited
@audio   -  nice      -19
EOF
    print_success "Realtime limits configured"
  else
    print_info "Realtime limits already configured"
  fi

  log_success "Realtime privileges configured"
}

# Configure system for low latency
configure_low_latency() {
  print_info "Configuring system for low latency audio..."

  # Create sysctl configuration
  local sysctl_file="/etc/sysctl.d/99-audio.conf"
  local sysctl_dir="/etc/sysctl.d"

  # Ensure directory exists
  if [[ ! -d "$sysctl_dir" ]]; then
    sudo mkdir -p "$sysctl_dir" || error_exit "Failed to create sysctl.d directory"
  fi

  sudo tee "$sysctl_file" >/dev/null <<EOF
# Audio latency optimizations
vm.swappiness=10
fs.inotify.max_user_watches=524288
EOF

  sudo sysctl -p "$sysctl_file" &>/dev/null || print_warning "Could not apply sysctl settings (will apply on reboot)"

  # Configure CPU governor for performance
  if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
      print_info "Setting CPU governor to performance mode..."
      local failed_cpus=0
      for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if ! echo "performance" | sudo tee "$cpu" &>/dev/null; then
          ((failed_cpus++))
        fi
      done

      if [[ $failed_cpus -eq 0 ]]; then
        print_success "CPU governor set to performance"
      else
        print_warning "Some CPUs could not be set to performance mode"
      fi
    else
      print_info "CPU frequency scaling not available (may be disabled or not supported)"
    fi
  else
    print_info "CPU frequency scaling not available on this system"
  fi

  print_success "Low latency optimizations applied"
}

# Configure PipeWire for audio production
configure_pipewire() {
  print_info "Configuring PipeWire for audio production..."

  local pw_config_dir="$HOME/.config/pipewire"
  local pw_conf_subdir="$pw_config_dir/pipewire.conf.d"

  # Ensure directory structure exists
  mkdir -p "$pw_conf_subdir" || error_exit "Failed to create PipeWire config directory"

  # Create optimized PipeWire configuration
  cat >"$pw_conf_subdir/99-audio-production.conf" <<'EOF'
# Audio production optimizations for PipeWire
context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 256
    default.clock.min-quantum = 64
    default.clock.max-quantum = 8192
}
EOF

  print_success "PipeWire configured for audio production"
}

################################################################################
# PACKAGE INSTALLATION FUNCTIONS
################################################################################

# Install a package with error handling
install_package() {
  local package=$1
  local use_aur=${2:-false}

  if $use_aur; then
    print_info "Installing $package from AUR..."
    if yay -S --noconfirm "$package" >>"$LOG_FILE" 2>&1; then
      print_success "$package installed"
      return 0
    else
      log_error "Failed to install $package"
      print_warning "Failed to install $package (check log for details)"
      return 1
    fi
  else
    print_info "Installing $package from official repos..."
    if sudo pacman -S --needed --noconfirm "$package" >>"$LOG_FILE" 2>&1; then
      print_success "$package installed"
      return 0
    else
      log_error "Failed to install $package"
      print_warning "Failed to install $package (check log for details)"
      return 1
    fi
  fi
}

# Install core system packages
install_core_system() {
  print_section "INSTALLING CORE SYSTEM COMPONENTS"

  local core_packages=(
    "pipewire-jack"
    "qpwgraph"
    "realtime-privileges"
    "dialog"
  )

  for package in "${core_packages[@]}"; do
    install_package "$package" false || print_warning "Could not install $package, continuing..."
  done

  print_success "Core system packages installed"
}

# Install selected kernel
install_kernel() {
  if [[ "${SELECTIONS[KERNEL_CHOICE]}" == "current" ]]; then
    return 0
  fi

  print_section "INSTALLING KERNEL"

  local kernel_package=""
  local kernel_headers=""

  case "${SELECTIONS[KERNEL_CHOICE]}" in
  "zen")
    kernel_package="linux-zen"
    kernel_headers="linux-zen-headers"
    ;;
  "rt")
    kernel_package="linux-rt"
    kernel_headers="linux-rt-headers"
    ;;
  esac

  if [[ -n "$kernel_package" ]]; then
    install_package "$kernel_package" true || error_exit "Failed to install $kernel_package"
    install_package "$kernel_headers" true || print_warning "Could not install kernel headers"

    print_success "Kernel installed successfully"
    print_warning "IMPORTANT: You must reboot to use the new kernel"
  fi
}

# Install Reaper and extensions
install_reaper() {
  print_section "INSTALLING REAPER DAW"

  # Install Reaper from official repos
  print_info "Installing Reaper DAW..."
  install_package "reaper" false || error_exit "Failed to install Reaper"

  # Install SWS Extensions from official repos
  print_info "Installing SWS Extensions..."
  install_package "sws" false || print_warning "Could not install SWS Extensions (continuing...)"

  # Install ReaPack from official repos
  print_info "Installing ReaPack..."
  install_package "reapack" false || print_warning "Could not install ReaPack (continuing...)"

  print_success "Reaper installation complete"
}

# Install yabridge if selected
install_yabridge_support() {
  if ! ${SELECTIONS[YABRIDGE]}; then
    return 0
  fi

  print_section "INSTALLING WINDOWS VST SUPPORT"

  local yabridge_packages=(
    "wine-staging"
    "yabridge"
    "yabridgectl"
  )

  for package in "${yabridge_packages[@]}"; do
    install_package "$package" true || print_warning "Could not install $package"
  done

  print_success "yabridge support installed"
  print_info "Run 'yabridgectl sync' after adding Windows VST paths"
}

# Install synthesizers
install_synthesizers() {
  local installed=false

  if ${SELECTIONS[VITAL]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING SYNTHESIZERS" && installed=true
    # Use vital-synth-vst-bin from AUR
    install_package "vital-synth-vst-bin" true || print_warning "Could not install Vital (continuing...)"
  fi

  if ${SELECTIONS[SURGE]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING SYNTHESIZERS" && installed=true
    install_package "surge-xt" false || print_warning "Could not install Surge XT (continuing...)"
  fi

  if ${SELECTIONS[DEXED]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING SYNTHESIZERS" && installed=true
    install_package "dexed" true || print_warning "Could not install Dexed (continuing...)"
  fi

  if ${SELECTIONS[HELM]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING SYNTHESIZERS" && installed=true
    install_package "helm-synth" true || print_warning "Could not install Helm (continuing...)"
  fi

  if ${SELECTIONS[ODIN2]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING SYNTHESIZERS" && installed=true
    install_package "odin2-synthesizer" true || print_warning "Could not install Odin 2 (continuing...)"
  fi

  if ${SELECTIONS[ZYN]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING SYNTHESIZERS" && installed=true
    install_package "zynaddsubfx" false || print_warning "Could not install ZynAddSubFX (continuing...)"
  fi

  $installed && print_success "Synthesizers installation complete"
}

# Install audio effects
install_effects() {
  local installed=false

  if ${SELECTIONS[DRAGONFLY]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING AUDIO EFFECTS" && installed=true
    install_package "dragonfly-reverb" false || print_warning "Could not install Dragonfly Reverb (continuing...)"
  fi

  if ${SELECTIONS[LSP]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING AUDIO EFFECTS" && installed=true
    install_package "lsp-plugins" false || print_warning "Could not install LSP Plugins (continuing...)"
  fi

  if ${SELECTIONS[X42]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING AUDIO EFFECTS" && installed=true
    install_package "x42-plugins" false || print_warning "Could not install x42-plugins (continuing...)"
  fi

  if ${SELECTIONS[CALF]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING AUDIO EFFECTS" && installed=true
    install_package "calf" false || print_warning "Could not install Calf Studio Gear (continuing...)"
  fi

  $installed && print_success "Audio effects installation complete"
}

# Install drum machines
install_drums() {
  local installed=false

  if ${SELECTIONS[HYDROGEN]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING DRUM MACHINES" && installed=true
    install_package "hydrogen" false || print_warning "Could not install Hydrogen (continuing...)"
  fi

  if ${SELECTIONS[DRUMGIZMO]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING DRUM MACHINES" && installed=true
    install_package "drumgizmo" false || print_warning "Could not install DrumGizmo (continuing...)"
  fi

  if ${SELECTIONS[DRUMKV1]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING DRUM MACHINES" && installed=true
    install_package "drumkv1" false || print_warning "Could not install drumkv1 (continuing...)"
  fi

  $installed && print_success "Drum machines installation complete"
}

# Install extra tools
install_extras() {
  local installed=false

  if ${SELECTIONS[CARLA]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING ADDITIONAL TOOLS" && installed=true
    install_package "carla" false || print_warning "Could not install Carla (continuing...)"
  fi

  if ${SELECTIONS[GUITARIX]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING ADDITIONAL TOOLS" && installed=true
    install_package "guitarix" false || print_warning "Could not install Guitarix (continuing...)"
  fi

  if ${SELECTIONS[SFIZZ]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING ADDITIONAL TOOLS" && installed=true
    install_package "sfizz" false || print_warning "Could not install sfizz (continuing...)"
  fi

  if ${SELECTIONS[QJACKCTL]}; then
    [[ "$installed" == false ]] && print_section "INSTALLING ADDITIONAL TOOLS" && installed=true
    install_package "qjackctl" false || print_warning "Could not install QjackCtl (continuing...)"
  fi

  $installed && print_success "Additional tools installation complete"
}

################################################################################
# POST-INSTALLATION
################################################################################

display_completion() {
  print_section "INSTALLATION COMPLETE!"

  echo -e "${COLOR_GREEN}${COLOR_BOLD}${SYMBOL_STAR} Congratulations! Your audio workstation is ready! ${SYMBOL_STAR}${COLOR_RESET}"
  echo ""

  echo -e "${COLOR_WHITE}${COLOR_BOLD}Next Steps:${COLOR_RESET}"
  echo ""

  if [[ "${SELECTIONS[KERNEL_CHOICE]}" != "current" ]]; then
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}1. REBOOT YOUR SYSTEM${COLOR_RESET}"
    echo "   You installed a new kernel. Reboot to activate it."
    echo "   Command: reboot"
    echo ""
  fi

  echo -e "${COLOR_CYAN}${COLOR_BOLD}2. Re-login or reboot${COLOR_RESET}"
  echo "   For realtime privileges to take effect, you need to log out and back in."
  echo ""

  echo -e "${COLOR_CYAN}${COLOR_BOLD}3. Start PipeWire${COLOR_RESET}"
  echo "   Ensure PipeWire is running:"
  echo "   systemctl --user restart pipewire pipewire-pulse"
  echo ""

  echo -e "${COLOR_CYAN}${COLOR_BOLD}4. Launch Reaper${COLOR_RESET}"
  echo "   Command: reaper"
  echo "   - Set audio device to PipeWire/JACK in Preferences > Audio"
  echo "   - Install ReaPack: Extensions > ReaPack > Browse packages"
  echo ""

  if ${SELECTIONS[YABRIDGE]}; then
    echo -e "${COLOR_MAGENTA}${COLOR_BOLD}5. Configure yabridge${COLOR_RESET}"
    echo "   Add your Windows VST directories:"
    echo "   yabridgectl add ~/.wine/drive_c/Program\\ Files/VSTPlugins"
    echo "   yabridgectl sync"
    echo ""
  fi

  echo -e "${COLOR_CYAN}${COLOR_BOLD}6. Test your setup${COLOR_RESET}"
  echo "   - Open qpwgraph to visualize audio connections"
  echo "   - Test latency with: jack_iodelay (if using JACK mode)"
  echo "   - Scan for plugins in Reaper: Options > Preferences > VST"
  echo ""

  echo -e "${COLOR_WHITE}${COLOR_BOLD}Useful Commands:${COLOR_RESET}"
  echo "  qpwgraph          - Visual audio/MIDI patchbay"
  echo "  pw-top            - PipeWire process monitor"
  echo "  reaper            - Launch Reaper DAW"
  if ${SELECTIONS[CARLA]}; then
    echo "  carla             - Plugin host and rack"
  fi
  if ${SELECTIONS[HYDROGEN]}; then
    echo "  hydrogen          - Drum machine"
  fi
  echo ""

  echo -e "${COLOR_WHITE}${COLOR_BOLD}Resources:${COLOR_RESET}"
  echo "  • Reaper Manual: https://www.reaper.fm/guides.php"
  echo "  • Linux Audio Wiki: https://wiki.archlinux.org/title/Professional_audio"
  echo "  • Installation log: $LOG_FILE"
  echo ""

  echo -e "${COLOR_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo -e "${COLOR_GREEN}${COLOR_BOLD}Happy music making! ${SYMBOL_MUSIC}${COLOR_RESET}"
  echo ""
}

################################################################################
# UNINSTALL FUNCTIONS
################################################################################

# Uninstall all packages installed by this script
uninstall_all_packages() {
  print_section "UNINSTALLING AUDIO PRODUCTION PACKAGES"

  echo -e "${COLOR_YELLOW}${COLOR_BOLD}WARNING: This will remove all audio production packages installed by this script.${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}Kernels (linux-zen, linux-rt) will NOT be removed for safety reasons.${COLOR_RESET}"
  echo ""
  read -p "Are you sure you want to continue? Type 'YES' to confirm: " confirm

  if [[ "$confirm" != "YES" ]]; then
    print_warning "Uninstallation cancelled"
    exit 0
  fi

  echo ""
  print_info "Starting uninstallation process..."

  # List of all packages that could have been installed
  local packages_to_remove=(
    # Core audio
    "qpwgraph"
    "realtime-privileges"

    # Reaper
    "reaper"
    "sws"
    "reapack"

    # VST Support
    "yabridge"
    "yabridgectl"
    "wine-staging"

    # Synthesizers
    "vital-synth-vst-bin"
    "surge-xt"
    "dexed"
    "helm-synth"
    "odin2-synthesizer"
    "zynaddsubfx"

    # Effects
    "dragonfly-reverb"
    "lsp-plugins"
    "x42-plugins"
    "calf"

    # Drums
    "hydrogen"
    "drumgizmo"
    "drumkv1"

    # Extra tools
    "carla"
    "guitarix"
    "sfizz"
    "qjackctl"
  )

  # Check which packages are actually installed
  local installed_packages=()
  print_info "Checking which packages are installed..."

  for package in "${packages_to_remove[@]}"; do
    if pacman -Qi "$package" &>/dev/null; then
      installed_packages+=("$package")
    fi
  done

  if [[ ${#installed_packages[@]} -eq 0 ]]; then
    print_success "No audio production packages found to remove"
    return 0
  fi

  echo ""
  echo -e "${COLOR_CYAN}${COLOR_BOLD}The following packages will be removed:${COLOR_RESET}"
  for package in "${installed_packages[@]}"; do
    echo "  • $package"
  done
  echo ""

  read -p "Proceed with removal? [Y/n]: " confirm
  case $confirm in
  [nN] | [nN][oO])
    print_warning "Uninstallation cancelled"
    exit 0
    ;;
  esac

  # Remove packages
  print_info "Removing packages..."
  if sudo pacman -Rns --noconfirm "${installed_packages[@]}" >>"$LOG_FILE" 2>&1; then
    print_success "Packages removed successfully"
  else
    print_warning "Some packages could not be removed (check log for details)"
  fi

  # Clean up configuration files
  print_info "Cleaning up configuration files..."

  # Remove PipeWire audio production config
  if [[ -f "$HOME/.config/pipewire/pipewire.conf.d/99-audio-production.conf" ]]; then
    rm -f "$HOME/.config/pipewire/pipewire.conf.d/99-audio-production.conf"
    print_success "Removed PipeWire audio production config"
  fi

  # Note about system configs (require manual removal with sudo)
  echo ""
  echo -e "${COLOR_YELLOW}${COLOR_BOLD}System Configuration Files:${COLOR_RESET}"
  echo "The following system configuration files were created and may need manual removal:"
  echo ""

  if [[ -f /etc/security/limits.d/99-realtime.conf ]]; then
    echo -e "  • ${COLOR_CYAN}/etc/security/limits.d/99-realtime.conf${COLOR_RESET} - Realtime audio privileges"
    echo "    Remove with: sudo rm /etc/security/limits.d/99-realtime.conf"
  fi

  if [[ -f /etc/sysctl.d/99-audio.conf ]]; then
    echo -e "  • ${COLOR_CYAN}/etc/sysctl.d/99-audio.conf${COLOR_RESET} - System latency optimizations"
    echo "    Remove with: sudo rm /etc/sysctl.d/99-audio.conf"
  fi

  echo ""
  echo -e "${COLOR_YELLOW}Note: Your user will remain in the 'audio' group.${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}Remove manually if needed: sudo gpasswd -d $USER audio${COLOR_RESET}"

  print_success "Uninstallation complete!"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  # Initialize
  init_logging
  print_header

  # System checks
  print_section "SYSTEM CHECKS"
  check_arch_linux
  check_not_root
  check_sudo
  check_internet
  check_pipewire
  check_yay

  press_any_key

  # Select mode (install or uninstall)
  select_mode

  # Handle uninstall mode
  if [[ "${SELECTIONS[MODE]}" == "uninstall" ]]; then
    uninstall_all_packages
    log_success "Uninstallation completed"
    exit 0
  fi

  # Continue with installation mode
  # Interactive selections
  select_kernel
  select_yabridge
  select_synthesizers
  select_effects
  select_drums
  select_extras

  # Display summary and confirm
  display_summary

  # System configuration
  print_section "CONFIGURING SYSTEM"
  configure_realtime
  configure_low_latency
  configure_pipewire

  # Install packages
  install_core_system
  install_kernel
  install_reaper
  install_yabridge_support
  install_synthesizers
  install_effects
  install_drums
  install_extras

  # Completion
  display_completion

  log_success "Installation completed successfully"
}

# Run main function
main "$@"
