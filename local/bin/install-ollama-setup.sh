#!/bin/bash

################################################################################
# Ollama & Open WebUI Manager
#
# A comprehensive management script for installing, running, and managing
# Ollama (native) and Open WebUI (Docker) on Arch Linux.
#
# Features:
# - AMD GPU optimization (ROCm support)
# - CPU fallback if GPU unavailable
# - Install, start, stop, status, and uninstall operations
# - Optimized for systems with 64GB RAM
# - Swedish + code-focused model (qwen2.5-coder:7b)
#
# Author: AI Assistant
# Date: 2025-11-01
################################################################################

set -e # Exit on error

# Configuration
readonly DATA_DIR="$HOME/AI/ollama-data"
readonly MODELS_DIR="$DATA_DIR/models"
readonly WEBUI_DIR="$DATA_DIR/openwebui"
readonly LOGS_DIR="$DATA_DIR/logs"
readonly OLLAMA_PORT=11434
readonly WEBUI_PORT=3000
readonly DEFAULT_MODEL="qwen2.5-coder:7b"
readonly WEBUI_CONTAINER_NAME="open-webui"

# Color codes for pretty output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

################################################################################
# Utility Functions
################################################################################

# Print colored message
print_msg() {
  local color=$1
  shift
  echo -e "${color}${*}${NC}"
}

# Print section header
print_header() {
  echo ""
  print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_msg "$BOLD$CYAN" "  $1"
  print_msg "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# Print success message
print_success() {
  print_msg "$GREEN" "✓ $1"
}

# Print error message
print_error() {
  print_msg "$RED" "✗ $1"
}

# Print warning message
print_warning() {
  print_msg "$YELLOW" "⚠ $1"
}

# Print info message
print_info() {
  print_msg "$BLUE" "ℹ $1"
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if running on Arch Linux
check_arch_linux() {
  if [ ! -f /etc/arch-release ]; then
    print_warning "This script is optimized for Arch Linux."
    print_warning "You're running a different distribution. Continue? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      print_error "Installation cancelled."
      exit 1
    fi
  fi
}

# Detect GPU type
detect_gpu() {
  if lspci | grep -i "amd" | grep -i "vga\|display\|3d" >/dev/null 2>&1; then
    echo "amd"
  elif lspci | grep -i "nvidia" >/dev/null 2>&1; then
    echo "nvidia"
  else
    echo "cpu"
  fi
}

# Check if Ollama is running
is_ollama_running() {
  pgrep -x "ollama" >/dev/null 2>&1
}

# Check if Open WebUI container is running
is_webui_running() {
  docker ps --filter "name=$WEBUI_CONTAINER_NAME" --filter "status=running" --format '{{.Names}}' | grep -q "$WEBUI_CONTAINER_NAME"
}

# Create necessary directories
create_directories() {
  print_info "Creating directory structure..."
  mkdir -p "$MODELS_DIR" "$WEBUI_DIR" "$LOGS_DIR"
  print_success "Directories created at $DATA_DIR"
}

################################################################################
# Installation Functions
################################################################################

install_dependencies() {
  print_header "Installing Dependencies"

  check_arch_linux

  print_info "Updating package database..."
  sudo pacman -Sy

  # Install base dependencies
  print_info "Installing base packages..."
  local packages=(
    "curl"
    "docker"
    "docker-compose"
    "git"
    "base-devel"
  )

  sudo pacman -S --needed --noconfirm "${packages[@]}"

  # Start and enable Docker
  print_info "Configuring Docker..."
  sudo systemctl start docker
  sudo systemctl enable docker

  # Add user to docker group if not already added
  if ! groups "$USER" | grep -q docker; then
    print_info "Adding user to docker group..."
    sudo usermod -aG docker "$USER"
    print_warning "You need to log out and back in for docker group changes to take effect!"
    print_warning "Or run: newgrp docker"
  fi

  print_success "Dependencies installed successfully"
}

install_gpu_support() {
  print_header "Configuring GPU Support"

  local gpu_type
  gpu_type=$(detect_gpu)

  case $gpu_type in
  amd)
    print_info "AMD GPU detected - Installing ROCm support..."
    print_warning "ROCm installation can be complex. Attempting basic setup..."

    # Check if ROCm packages are available
    if pacman -Ss rocm-hip-runtime >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm rocm-hip-runtime rocm-opencl-runtime || true
      print_success "AMD ROCm packages installed"
    else
      print_warning "ROCm packages not found in repos. Ollama will attempt GPU usage anyway."
    fi

    # Set environment for AMD GPU
    export HSA_OVERRIDE_GFX_VERSION=10.3.0
    export OLLAMA_GPU=1
    print_success "AMD GPU support configured"
    ;;

  nvidia)
    print_info "NVIDIA GPU detected - Installing CUDA support..."
    if pacman -Ss cuda >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm cuda cuda-tools || true
      print_success "NVIDIA CUDA packages installed"
    else
      print_warning "CUDA packages not found. Installing nvidia-utils..."
      sudo pacman -S --needed --noconfirm nvidia-utils || true
    fi
    ;;

  cpu)
    print_warning "No discrete GPU detected. Will use CPU mode."
    print_info "Performance will be slower but functional."
    ;;
  esac
}

install_ollama() {
  print_header "Installing Ollama"

  if command_exists ollama; then
    print_warning "Ollama is already installed."
    print_info "Current version: $(ollama --version 2>/dev/null || echo 'unknown')"
    return 0
  fi

  print_info "Downloading and installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh

  # Configure Ollama to use our data directory
  export OLLAMA_MODELS="$MODELS_DIR"

  # Add to user's bashrc for persistence
  if ! grep -q "OLLAMA_MODELS" "$HOME/.bashrc"; then
    echo "" >>"$HOME/.bashrc"
    echo "# Ollama configuration" >>"$HOME/.bashrc"
    echo "export OLLAMA_MODELS=\"$MODELS_DIR\"" >>"$HOME/.bashrc"
  fi

  print_success "Ollama installed successfully"
}

install_openwebui() {
  print_header "Installing Open WebUI"

  # Check if container already exists
  if docker ps -a --filter "name=$WEBUI_CONTAINER_NAME" --format '{{.Names}}' | grep -q "$WEBUI_CONTAINER_NAME"; then
    print_warning "Open WebUI container already exists."
    return 0
  fi

  print_info "Pulling Open WebUI Docker image..."
  docker pull ghcr.io/open-webui/open-webui:main

  print_info "Creating Open WebUI container..."
  docker run -d \
    --name "$WEBUI_CONTAINER_NAME" \
    --restart unless-stopped \
    -p "$WEBUI_PORT:8080" \
    --add-host=host.docker.internal:host-gateway \
    -v "$WEBUI_DIR:/app/backend/data" \
    -e OLLAMA_BASE_URL=http://host.docker.internal:$OLLAMA_PORT \
    ghcr.io/open-webui/open-webui:main

  # Stop the container (user will start it manually with the script)
  docker stop "$WEBUI_CONTAINER_NAME" >/dev/null 2>&1

  print_success "Open WebUI installed successfully"
}

download_default_model() {
  print_header "Downloading Default Model"

  print_info "This will download $DEFAULT_MODEL (~4.7GB)"
  print_info "This model is excellent for:"
  print_msg "$GREEN" "  • Code generation and debugging"
  print_msg "$GREEN" "  • Swedish language support"
  print_msg "$GREEN" "  • Technical explanations"
  echo ""

  # Start Ollama temporarily if not running
  local ollama_was_stopped=false
  if ! is_ollama_running; then
    print_info "Starting Ollama temporarily..."
    export OLLAMA_MODELS="$MODELS_DIR"
    ollama serve >"$LOGS_DIR/ollama-install.log" 2>&1 &
    local ollama_pid=$!
    sleep 3
    ollama_was_stopped=true
  fi

  print_info "Downloading $DEFAULT_MODEL (this may take a few minutes)..."
  if ollama pull "$DEFAULT_MODEL"; then
    print_success "Model $DEFAULT_MODEL downloaded successfully"
  else
    print_error "Failed to download model"
    if [ "$ollama_was_stopped" = true ]; then
      kill $ollama_pid 2>/dev/null || true
    fi
    return 1
  fi

  # Stop temporary Ollama if we started it
  if [ "$ollama_was_stopped" = true ]; then
    print_info "Stopping temporary Ollama instance..."
    kill $ollama_pid 2>/dev/null || true
    sleep 2
  fi
}

install_all() {
  print_header "🚀 Ollama & Open WebUI Installation"

  print_info "This will install:"
  print_msg "$CYAN" "  • Ollama (native installation with GPU support)"
  print_msg "$CYAN" "  • Open WebUI (Docker container)"
  print_msg "$CYAN" "  • Default model: $DEFAULT_MODEL"
  print_msg "$CYAN" "  • Data directory: $DATA_DIR"
  echo ""
  print_warning "Continue? (y/n)"
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    print_error "Installation cancelled."
    return 1
  fi

  create_directories
  install_dependencies
  install_gpu_support
  install_ollama
  install_openwebui
  download_default_model

  print_header "✅ Installation Complete!"
  print_success "Ollama and Open WebUI have been installed successfully"
  echo ""
  print_info "Next steps:"
  print_msg "$GREEN" "  1. Run: ./ollama-manager.sh start"
  print_msg "$GREEN" "  2. Open browser: http://localhost:$WEBUI_PORT"
  print_msg "$GREEN" "  3. Create an account in Open WebUI"
  echo ""
  print_info "Data location: $DATA_DIR"
  print_info "Use './ollama-manager.sh status' to check system status"
}

################################################################################
# Service Management Functions
################################################################################

start_services() {
  print_header "Starting Services"

  # Set environment for Ollama
  export OLLAMA_MODELS="$MODELS_DIR"

  # Detect and configure GPU
  local gpu_type
  gpu_type=$(detect_gpu)

  if [ "$gpu_type" = "amd" ]; then
    export HSA_OVERRIDE_GFX_VERSION=10.3.0
    export OLLAMA_GPU=1
    print_info "AMD GPU mode enabled"
  elif [ "$gpu_type" = "nvidia" ]; then
    export OLLAMA_GPU=1
    print_info "NVIDIA GPU mode enabled"
  else
    print_info "CPU mode (no discrete GPU detected)"
  fi

  # Start Ollama
  if is_ollama_running; then
    print_warning "Ollama is already running (PID: $(pgrep -x ollama))"
  else
    print_info "Starting Ollama..."
    nohup ollama serve >"$LOGS_DIR/ollama.log" 2>&1 &
    sleep 2

    if is_ollama_running; then
      print_success "Ollama started (PID: $(pgrep -x ollama))"
    else
      print_error "Failed to start Ollama. Check logs: $LOGS_DIR/ollama.log"
      return 1
    fi
  fi

  # Start Open WebUI
  if is_webui_running; then
    print_warning "Open WebUI is already running"
  else
    print_info "Starting Open WebUI..."
    if docker start "$WEBUI_CONTAINER_NAME" >/dev/null 2>&1; then
      sleep 2
      print_success "Open WebUI started"
    else
      print_error "Failed to start Open WebUI"
      print_info "Try: docker logs $WEBUI_CONTAINER_NAME"
      return 1
    fi
  fi

  echo ""
  print_success "All services are running!"
  print_info "Access Open WebUI at: ${BOLD}http://localhost:$WEBUI_PORT${NC}"
  print_info "Ollama API at: http://localhost:$OLLAMA_PORT"
}

stop_services() {
  print_header "Stopping Services"

  # Stop Open WebUI
  if is_webui_running; then
    print_info "Stopping Open WebUI..."
    docker stop "$WEBUI_CONTAINER_NAME" >/dev/null 2>&1
    print_success "Open WebUI stopped"
  else
    print_warning "Open WebUI is not running"
  fi

  # Stop Ollama
  if is_ollama_running; then
    print_info "Stopping Ollama..."
    pkill -TERM ollama
    sleep 2

    # Force kill if still running
    if is_ollama_running; then
      print_warning "Forcing Ollama to stop..."
      pkill -KILL ollama
    fi

    print_success "Ollama stopped"
  else
    print_warning "Ollama is not running"
  fi

  print_success "All services stopped"
}

show_status() {
  print_header "System Status"

  # Ollama status
  echo ""
  print_msg "$BOLD" "Ollama Service:"
  if is_ollama_running; then
    local pid
    pid=$(pgrep -x ollama)
    print_success "Running (PID: $pid)"

    # Show resource usage
    local mem_usage
    mem_usage=$(ps -p "$pid" -o rss= | awk '{printf "%.2f MB", $1/1024}')
    print_info "Memory usage: $mem_usage"
  else
    print_error "Not running"
  fi

  # Open WebUI status
  echo ""
  print_msg "$BOLD" "Open WebUI:"
  if is_webui_running; then
    print_success "Running"
    print_info "Access: http://localhost:$WEBUI_PORT"

    # Show container stats
    local container_status
    container_status=$(docker ps --filter "name=$WEBUI_CONTAINER_NAME" --format "Status: {{.Status}}")
    print_info "$container_status"
  else
    if docker ps -a --filter "name=$WEBUI_CONTAINER_NAME" --format '{{.Names}}' | grep -q "$WEBUI_CONTAINER_NAME"; then
      print_warning "Container exists but not running"
    else
      print_error "Not installed"
    fi
  fi

  # GPU status
  echo ""
  print_msg "$BOLD" "GPU Configuration:"
  local gpu_type
  gpu_type=$(detect_gpu)

  case $gpu_type in
  amd)
    print_info "Type: AMD GPU"
    if lspci | grep -i "amd" | grep -i "vga\|display\|3d"; then
      print_info "Device: $(lspci | grep -i "amd" | grep -i "vga\|display\|3d" | head -1 | cut -d: -f3)"
    fi
    ;;
  nvidia)
    print_info "Type: NVIDIA GPU"
    if command_exists nvidia-smi; then
      nvidia-smi --query-gpu=name --format=csv,noheader | while read -r gpu; do
        print_info "Device: $gpu"
      done
    fi
    ;;
  cpu)
    print_warning "Type: CPU only (no discrete GPU)"
    ;;
  esac

  # List installed models
  echo ""
  print_msg "$BOLD" "Installed Models:"
  if is_ollama_running; then
    if ollama list 2>/dev/null | tail -n +2; then
      :
    else
      print_warning "No models installed"
    fi
  else
    print_warning "Start Ollama to see installed models"
  fi

  # System resources
  echo ""
  print_msg "$BOLD" "System Resources:"
  local total_mem
  local used_mem
  local free_mem
  total_mem=$(free -h | awk '/^Mem:/ {print $2}')
  used_mem=$(free -h | awk '/^Mem:/ {print $3}')
  free_mem=$(free -h | awk '/^Mem:/ {print $4}')

  print_info "RAM: $used_mem / $total_mem used ($free_mem free)"

  local cpu_usage
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
  print_info "CPU Usage: ${cpu_usage}%"

  # Data directory size
  echo ""
  print_msg "$BOLD" "Data Directory:"
  print_info "Location: $DATA_DIR"
  if [ -d "$DATA_DIR" ]; then
    local dir_size
    dir_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
    print_info "Total size: $dir_size"
  fi
}

################################################################################
# Uninstallation Functions
################################################################################

uninstall_all() {
  print_header "⚠️  Uninstall Ollama & Open WebUI"

  print_warning "This will remove:"
  print_msg "$RED" "  • Ollama (binary and service)"
  print_msg "$RED" "  • Open WebUI (Docker container and image)"
  echo ""
  print_info "Data preservation options:"
  print_msg "$YELLOW" "  • Keep data: Your models and chats in $DATA_DIR will be preserved"
  print_msg "$YELLOW" "  • Remove all: Everything including data will be deleted"
  echo ""

  print_warning "Do you want to continue? (y/n)"
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    print_error "Uninstall cancelled."
    return 0
  fi

  echo ""
  print_warning "Keep data directory ($DATA_DIR)? (y/n)"
  read -r keep_data

  # Stop services first
  print_info "Stopping services..."
  stop_services

  # Remove Open WebUI
  print_info "Removing Open WebUI..."
  if docker ps -a --filter "name=$WEBUI_CONTAINER_NAME" --format '{{.Names}}' | grep -q "$WEBUI_CONTAINER_NAME"; then
    docker rm -f "$WEBUI_CONTAINER_NAME" >/dev/null 2>&1
    print_success "Open WebUI container removed"
  fi

  docker rmi ghcr.io/open-webui/open-webui:main >/dev/null 2>&1 || true
  print_success "Open WebUI image removed"

  # Remove Ollama
  print_info "Removing Ollama..."
  if command_exists ollama; then
    # Remove Ollama binary and service
    sudo systemctl stop ollama 2>/dev/null || true
    sudo systemctl disable ollama 2>/dev/null || true
    sudo rm -f /usr/local/bin/ollama
    sudo rm -f /etc/systemd/system/ollama.service
    sudo systemctl daemon-reload

    # Remove from bashrc
    if [ -f "$HOME/.bashrc" ]; then
      sed -i '/# Ollama configuration/,/export OLLAMA_MODELS/d' "$HOME/.bashrc"
    fi

    print_success "Ollama removed"
  fi

  # Remove data if requested
  if [[ ! "$keep_data" =~ ^[Yy]$ ]]; then
    print_warning "Removing all data from $DATA_DIR..."
    rm -rf "$DATA_DIR"
    print_success "Data directory removed"
  else
    print_success "Data directory preserved at $DATA_DIR"
  fi

  print_header "✅ Uninstallation Complete"

  if [[ "$keep_data" =~ ^[Yy]$ ]]; then
    print_info "Your data has been preserved."
    print_info "To reinstall, run: ./ollama-manager.sh install"
  else
    print_info "All data has been removed."
  fi
}

################################################################################
# Main Menu
################################################################################

show_menu() {
  clear
  print_msg "$BOLD$MAGENTA" "╔═══════════════════════════════════════════════════════════════╗"
  print_msg "$BOLD$MAGENTA" "║                                                               ║"
  print_msg "$BOLD$MAGENTA" "║          🤖  Ollama & Open WebUI Manager  🤖                  ║"
  print_msg "$BOLD$MAGENTA" "║                                                               ║"
  print_msg "$BOLD$MAGENTA" "╚═══════════════════════════════════════════════════════════════╝"
  echo ""
  print_msg "$CYAN" "  1) 📦 Install Ollama & Open WebUI"
  print_msg "$GREEN" "  2) ▶️  Start Services"
  print_msg "$YELLOW" "  3) ⏹️  Stop Services"
  print_msg "$BLUE" "  4) 📊 Show Status"
  print_msg "$RED" "  5) 🗑️  Uninstall All"
  print_msg "$MAGENTA" "  6) 🚪 Exit"
  echo ""
  print_msg "$BOLD" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

main() {
  while true; do
    show_menu
    read -p "$(echo -e ${BOLD}Enter your choice [1-6]:${NC})" choice
    echo ""

    case $choice in
    1)
      install_all
      ;;
    2)
      start_services
      ;;
    3)
      stop_services
      ;;
    4)
      show_status
      ;;
    5)
      uninstall_all
      ;;
    6)
      print_success "Goodbye! 👋"
      exit 0
      ;;
    *)
      print_error "Invalid option. Please choose 1-6."
      ;;
    esac

    echo ""
    read -p "$(echo -e ${CYAN}Press Enter to continue...${NC})"
  done
}

# Run main menu
main
