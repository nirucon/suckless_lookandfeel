#!/bin/bash

# arch-maintenance.sh
# Maintenance script for Arch Linux
# Cleans cache, orphaned packages, old logs, downloads, screenshots etc.

set -e # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Log file
LOGFILE="$HOME/.cache/arch-maintenance.log"
mkdir -p "$(dirname "$LOGFILE")"

# Logging functions
log() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOGFILE"
}

error() {
  echo -e "${RED}${BOLD}[ERROR]${NC} $1" | tee -a "$LOGFILE"
}

warn() {
  echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1" | tee -a "$LOGFILE"
}

info() {
  echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}${BOLD}[✓]${NC} $1"
}

header() {
  echo ""
  echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${MAGENTA}${BOLD}║${NC} $(printf "%-62s" "$1") ${MAGENTA}${BOLD}║${NC}"
  echo -e "${MAGENTA}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

separator() {
  echo -e "${BLUE}────────────────────────────────────────────────────────────────${NC}"
}

# Ensure script is run as regular user (we'll use sudo where needed)
if [ "$EUID" -eq 0 ]; then
  error "Do not run this script as root! Use your regular user account."
  exit 1
fi

# Check disk space before cleaning
DISK_BEFORE=$(df -h / | awk 'NR==2 {print $4}')

# Main header
clear
echo -e "${BOLD}${MAGENTA}"
echo "    ╔═══════════════════════════════════════════════════════╗"
echo "    ║                                                       ║"
echo "    ║         ARCH LINUX MAINTENANCE SCRIPT                 ║"
echo "    ║                                                       ║"
echo "    ╚═══════════════════════════════════════════════════════╝"
echo -e "${NC}"

log "=== Starting Arch Linux maintenance ==="
info "Free disk space before cleaning: ${BOLD}$DISK_BEFORE${NC}"
separator

# ============================================
# 1. System update
# ============================================
header "1. System Update"
info "Checking for system updates..."
if sudo pacman -Syu --noconfirm; then
  success "System updated successfully"
else
  warn "System update failed or was cancelled"
fi

# ============================================
# 2. Clean pacman cache
# ============================================
header "2. Pacman Cache Cleanup"
info "Current cache size:"
CACHE_SIZE=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
echo -e "  ${BOLD}$CACHE_SIZE${NC}"

# Keep last 2 versions of installed packages
if command -v paccache &>/dev/null; then
  info "Removing old package versions (keeping last 2)..."
  sudo paccache -r -k 2

  info "Removing cache for uninstalled packages..."
  sudo paccache -r -u -k 0

  success "Pacman cache cleaned (kept 2 latest versions)"
else
  warn "paccache not installed, skipping (install pacman-contrib package)"
fi

# ============================================
# 3. Remove orphaned packages
# ============================================
header "3. Orphaned Packages"
info "Searching for orphaned packages..."
ORPHANS=$(pacman -Qtdq 2>/dev/null)

if [ -n "$ORPHANS" ]; then
  ORPHAN_COUNT=$(echo "$ORPHANS" | wc -l)
  warn "Found ${BOLD}$ORPHAN_COUNT${NC} orphaned packages:"
  echo ""
  echo "$ORPHANS" | sed 's/^/  • /'
  echo ""
  read -p "$(echo -e ${YELLOW}Remove these packages? [y/N]:${NC})" -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo pacman -Rns --noconfirm $ORPHANS
    success "Removed $ORPHAN_COUNT orphaned packages"
  else
    info "Skipped orphaned package removal"
  fi
else
  success "No orphaned packages found"
fi

# ============================================
# 4. Clean AUR helper cache (yay/paru)
# ============================================
header "4. AUR Helper Cache Cleanup"

# Check for yay
if [ -d "$HOME/.cache/yay" ]; then
  YAY_SIZE=$(du -sh "$HOME/.cache/yay" 2>/dev/null | cut -f1)
  info "yay cache size: ${BOLD}$YAY_SIZE${NC}"
  if command -v yay &>/dev/null; then
    yay -Sc --noconfirm 2>/dev/null || true
    success "yay cache cleaned"
  fi
fi

# Check for paru
if [ -d "$HOME/.cache/paru" ]; then
  PARU_SIZE=$(du -sh "$HOME/.cache/paru" 2>/dev/null | cut -f1)
  info "paru cache size: ${BOLD}$PARU_SIZE${NC}"
  if command -v paru &>/dev/null; then
    paru -Sc --noconfirm 2>/dev/null || true
    success "paru cache cleaned"
  fi
fi

if [ ! -d "$HOME/.cache/yay" ] && [ ! -d "$HOME/.cache/paru" ]; then
  info "No AUR helper cache found"
fi

# ============================================
# 5. Clean systemd journal
# ============================================
header "5. Systemd Journal Cleanup"
JOURNAL_SIZE=$(sudo journalctl --disk-usage | grep -oP '\d+\.\d+[GM]' | head -1)
info "Current journal size: ${BOLD}$JOURNAL_SIZE${NC}"

# Keep only last 2 weeks
info "Cleaning journal (keeping last 2 weeks)..."
sudo journalctl --vacuum-time=2weeks
success "Journal cleaned"

# ============================================
# 6. Clean user cache (selective)
# ============================================
header "6. User Cache Cleanup (Selective)"

if [ -d "$HOME/.cache" ]; then
  # Only clean specific safe directories, not everything
  SAFE_TO_CLEAN=(
    "thumbnails"
    "mozilla/firefox/*/thumbnails"
  )

  for dir in "${SAFE_TO_CLEAN[@]}"; do
    # Handle wildcards in path
    for target in $HOME/.cache/$dir; do
      if [ -d "$target" ]; then
        SIZE=$(du -sh "$target" 2>/dev/null | cut -f1)
        info "Cleaning $(basename "$target"): ${BOLD}$SIZE${NC}"
        rm -rf "$target"/* 2>/dev/null || true
      fi
    done
  done
  success "Selective cache cleanup completed"
else
  info "No user cache directory found"
fi

# ============================================
# 7. Clean Screenshots (NOT the SAVE folder!)
# ============================================
header "7. Screenshots Cleanup"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
SAVE_DIR="$SCREENSHOT_DIR/SAVE"

if [ -d "$SCREENSHOT_DIR" ]; then
  # Count files before (exclude subdirectories, only files in root)
  COUNT_BEFORE=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)

  if [ $COUNT_BEFORE -gt 0 ]; then
    SIZE_BEFORE=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
    warn "Found ${BOLD}$COUNT_BEFORE${NC} screenshot files (${BOLD}$SIZE_BEFORE${NC})"

    # Show that SAVE folder will be preserved
    if [ -d "$SAVE_DIR" ]; then
      SAVED_COUNT=$(find "$SAVE_DIR" -type f | wc -l)
      info "SAVE folder contains ${BOLD}$SAVED_COUNT${NC} files (will be preserved)"
    fi

    echo ""
    read -p "$(echo -e ${YELLOW}Delete $COUNT_BEFORE screenshots? \(SAVE folder is safe\) [y/N]:${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # Delete ONLY files directly in Screenshots root, not subdirectories
      find "$SCREENSHOT_DIR" -maxdepth 1 -type f -delete
      COUNT_AFTER=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f | wc -l)
      success "Deleted $((COUNT_BEFORE - COUNT_AFTER)) screenshot files"

      # Verify SAVE folder is intact
      if [ -d "$SAVE_DIR" ]; then
        SAVED_COUNT=$(find "$SAVE_DIR" -type f | wc -l)
        success "SAVE folder intact: ${BOLD}$SAVED_COUNT${NC} files preserved ✓"
      fi
    else
      info "Skipped screenshot cleanup"
    fi
  else
    success "No screenshots to clean"
  fi
else
  info "Screenshots directory not found"
fi

# ============================================
# 8. Clean Downloads folder
# ============================================
header "8. Downloads Cleanup"
DOWNLOADS_DIR="$HOME/Downloads"

if [ -d "$DOWNLOADS_DIR" ]; then
  # Count all files (not directories)
  COUNT_FILES=$(find "$DOWNLOADS_DIR" -type f | wc -l)

  if [ $COUNT_FILES -gt 0 ]; then
    SIZE_DOWNLOADS=$(du -sh "$DOWNLOADS_DIR" 2>/dev/null | cut -f1)
    warn "Found ${BOLD}$COUNT_FILES${NC} files in Downloads (${BOLD}$SIZE_DOWNLOADS${NC})"

    # Show a preview of what's in there
    info "Most recent files:"
    ls -lt "$DOWNLOADS_DIR" | head -6 | tail -5 | awk '{print "  • " $9}' 2>/dev/null || true

    echo ""
    read -p "$(echo -e ${YELLOW}Delete all files in Downloads? [y/N]:${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # Delete all files but preserve directory structure
      find "$DOWNLOADS_DIR" -type f -delete
      COUNT_AFTER=$(find "$DOWNLOADS_DIR" -type f | wc -l)
      success "Deleted $((COUNT_FILES - COUNT_AFTER)) files from Downloads"
    else
      info "Skipped Downloads cleanup"
    fi
  else
    success "Downloads folder is already empty"
  fi
else
  info "Downloads directory not found"
fi

# ============================================
# 9. Clean trash
# ============================================
header "9. Trash Cleanup"
TRASH_DIR="$HOME/.local/share/Trash"

if [ -d "$TRASH_DIR" ]; then
  SIZE=$(du -sh "$TRASH_DIR" 2>/dev/null | cut -f1)
  info "Trash size: ${BOLD}$SIZE${NC}"
  rm -rf "$TRASH_DIR"/* 2>/dev/null || true
  success "Trash emptied"
else
  info "No trash directory found"
fi

# ============================================
# 10. Find broken symlinks
# ============================================
header "10. Broken Symlinks"
info "Searching for broken symlinks in home directory..."
BROKEN_LINKS=$(find "$HOME" -xtype l 2>/dev/null)

if [ -n "$BROKEN_LINKS" ]; then
  BROKEN_COUNT=$(echo "$BROKEN_LINKS" | wc -l)
  warn "Found ${BOLD}$BROKEN_COUNT${NC} broken symlinks:"
  echo ""
  echo "$BROKEN_LINKS" | sed 's/^/  • /'
  echo ""
  read -p "$(echo -e ${YELLOW}Remove these broken symlinks? [y/N]:${NC})" -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    find "$HOME" -xtype l -delete 2>/dev/null
    success "Broken symlinks removed"
  else
    info "Skipped broken symlink removal"
  fi
else
  success "No broken symlinks found"
fi

# ============================================
# 11. Optimize pacman database
# ============================================
header "11. Pacman Database Optimization"
info "Optimizing pacman database..."
sudo pacman-optimize 2>/dev/null || warn "pacman-optimize failed (might already be optimized)"
success "Pacman database optimized"

# ============================================
# Summary
# ============================================
header "MAINTENANCE COMPLETE"

# Check disk space after cleaning
DISK_AFTER=$(df -h / | awk 'NR==2 {print $4}')

echo -e "${GREEN}${BOLD}✓ All maintenance tasks completed successfully!${NC}"
echo ""
echo -e "${CYAN}${BOLD}Disk Space Summary:${NC}"
echo -e "  Before: ${BOLD}$DISK_BEFORE${NC}"
echo -e "  After:  ${BOLD}${GREEN}$DISK_AFTER${NC}"
echo ""
echo -e "${CYAN}${BOLD}Log file:${NC} $LOGFILE"
echo ""

log "=== Maintenance completed successfully ==="

# Final decorative separator
echo -e "${MAGENTA}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
