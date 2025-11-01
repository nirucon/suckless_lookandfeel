#!/usr/bin/env bash
# DWM status bar for Arch Linux
# ------------------------------------------------------------
# Shows (left → right): CLIPBOARD | VOLUME | BATTERY | TEMP | WIFI | NEXTCLOUD | BLUETOOTH | MUSIC | UPDATES | DISK | DATE | TIME
# The bar is resilient: each part tolerates missing tools and falls back to "n/a".
#
# Design goals:
# - Robust on multiple Arch installs (different PATHs/backends).
# - No racing at boot: waits for NetworkManager to be "connected".
# - SSID via ACTIVE connection (nmcli), not via scan list.
# - Minimal dependencies; graceful degradation.
# - Event-driven volume updates (fast response to volume key presses).
# - Dynamic parts: music, updates, disk only shown when relevant.
# - Hardware adaptive: battery, WiFi, and Bluetooth only shown if hardware exists.
# - Suspend/resume resilient: detects time jumps and updates immediately.
#
# Dependencies (install if missing):
#   pacman-contrib  (for checkupdates)
#   playerctl       (for music info from cmus/spotify/mpv)
#
# Environment variables (optional):
#   DWM_STATUS_ICONS=1        # 1 = use icons when possible (default), 0 = text-only
#   DWM_STATUS_ASSUME_ICONS=0 # 1 = force icons even if unsure
#   DWM_STATUS_INTERVAL=10    # refresh interval (seconds)
#   DWM_STATUS_WIFI_CMD=iwgetid|nmcli  # force SSID source
#   DWM_STATUS_NET_PING=1.1.1.1        # ping target for connectivity (default 1.1.1.1)
#   DWM_STATUS_TEMP_WARN=75   # CPU temp warning threshold (°C)
#   DWM_STATUS_DISK_WARN=15   # Disk usage warning threshold (%)
#   DWM_STATUS_UPDATES_CACHE=900   # Updates cache time (seconds, default 15min)

set -Eeuo pipefail
IFS=$'\n\t'

# ---- Absolute paths (avoid PATH issues in autostart sessions) ----------------
NMCLI="/usr/bin/nmcli"
AWK="/usr/bin/awk"
IWGETID="/usr/bin/iwgetid"
IW="/usr/bin/iw"
PING="/usr/bin/ping"
DATE="/usr/bin/date"
XSETROOT="/usr/bin/xsetroot"
WPCTL="/usr/bin/wpctl"
PACTL="/usr/bin/pactl"
GREP="/usr/bin/grep"
SED="/usr/bin/sed"
PLAYERCTL="/usr/bin/playerctl"
CHECKUPDATES="/usr/bin/checkupdates"
BLUETOOTHCTL="/usr/bin/bluetoothctl"
DF="/usr/bin/df"

# Ensure a sane PATH for any sub-processes (keeps user overrides last)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# -----------------------------
# Configuration
# -----------------------------
TEMP_WARN=${DWM_STATUS_TEMP_WARN:-75}
DISK_WARN=${DWM_STATUS_DISK_WARN:-15}
UPDATES_CACHE=${DWM_STATUS_UPDATES_CACHE:-900} # 15 min cache (was 30 min)

# Hardware detection cache (set once at startup)
HAS_BATTERY=""
HAS_WIFI=""
HAS_BLUETOOTH=""

# -----------------------------
# Helpers
# -----------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; } # PATH-based check
has_bin() { [ -x "$1" ]; }                     # absolute-path check
trim() { $SED 's/^[[:space:]]\+//;s/[[:space:]]\+$//'; }

# -----------------------------
# Hardware detection
# -----------------------------
detect_hardware() {
  # Check for battery
  if ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    HAS_BATTERY="yes"
  else
    HAS_BATTERY="no"
  fi

  # Check for WiFi adapter
  if ls /sys/class/net/wl* >/dev/null 2>&1 ||
    [ -d /sys/class/ieee80211 ] ||
    (has_bin "$NMCLI" && "$NMCLI" device 2>/dev/null | $GREP -q wifi) ||
    (has_bin "$IW" && "$IW" dev 2>/dev/null | $GREP -q Interface); then
    HAS_WIFI="yes"
  else
    HAS_WIFI="no"
  fi

  # Check for Bluetooth
  if [ -d /sys/class/bluetooth ] && ls /sys/class/bluetooth/hci* >/dev/null 2>&1; then
    HAS_BLUETOOTH="yes"
  elif has_bin "$BLUETOOTHCTL" && "$BLUETOOTHCTL" show 2>/dev/null | $GREP -q "Controller"; then
    HAS_BLUETOOTH="yes"
  else
    HAS_BLUETOOTH="no"
  fi
}

# -----------------------------
# Icon / text mode
# -----------------------------
ICONS=${DWM_STATUS_ICONS:-1}
ASSUME=${DWM_STATUS_ASSUME_ICONS:-1}

use_icons() {
  # If you KNOW you run a Nerd Font in the bar, set ASSUME=1 to always use icons.
  if [ "$ASSUME" = "1" ]; then return 0; fi
  [ "$ICONS" = "1" ] && return 0 || return 1
}

# -----------------------------
# Glyphs (Nerd Font). Text fallbacks are used in each part function.
# -----------------------------
icon_bat() { echo -ne '\uf240'; }        # battery default (level-specific used below)
icon_plug() { echo -ne '\uf1e6'; }       # AC/charging
icon_wifi() { echo -ne '\uf1eb'; }       # Wi-Fi
icon_cloud() { echo -ne '\uf0c2'; }      # Nextcloud online
icon_cloud_sync() { echo -ne '\uf021'; } # Nextcloud syncing
icon_cloud_off() { echo -ne '\uf127'; }  # Nextcloud offline
icon_spk() { echo -ne '\uf028'; }        # volume
icon_spk_mute() { echo -ne '\uf6a9'; }   # clearer mute icon
icon_bt() { echo -ne '\uf293'; }         # bluetooth
icon_music() { echo -ne '\u266b'; }      # music playing
icon_temp() { echo -ne '\uf2db'; }       # temperature
icon_fire() { echo -ne '\U1f525'; }      # temperature warning
icon_updates() { echo -ne '\uf303'; }    # updates available
icon_disk() { echo -ne '\u26a0'; }       # disk warning
icon_clip() { echo -ne '\uf0ea'; }       # clipboard
icon_sep() { echo -ne ' | '; }           # separator

# -----------------------------
# Signal handling for fast volume updates
# -----------------------------
FORCE_UPDATE=0
trap 'FORCE_UPDATE=1' SIGUSR1

# -----------------------------
# Volume (PipeWire via wpctl)
# -----------------------------
volume_part() {
  if ! has_bin "$WPCTL"; then
    use_icons && printf " n/a" || printf "Vol: n/a"
    return
  fi
  local line mute vol pct
  line=$("$WPCTL" get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
  # Typical outputs:
  #  "Volume: 0.34"
  #  "Volume: 0.34 [MUTED]"
  mute=$(printf '%s\n' "$line" | $GREP -Eoi 'MUTED' | head -n1 || true)
  vol=$(printf '%s\n' "$line" | $AWK '/Volume:/ {print $2}')
  if [ -z "${vol:-}" ]; then
    use_icons && printf " n/a" || printf "Vol: n/a"
    return
  fi
  pct=$($AWK -v v="$vol" 'BEGIN{printf("%d", v*100+0.5)}')
  if [ -n "${mute:-}" ]; then
    use_icons && printf "%s %s%%" "$(icon_spk_mute)" "$pct" || printf "Vol*: %s%%" "$pct"
  else
    use_icons && printf "%s %s%%" "$(icon_spk)" "$pct" || printf "Vol: %s%%" "$pct"
  fi
}

# -----------------------------
# Volume event listener (background process)
# Monitors PipeWire/PulseAudio events and sends SIGUSR1 to main process
# Resilient to suspend/resume: auto-restarts if connection breaks
# -----------------------------
volume_listener() {
  local main_pid=$1
  if ! has_bin "$PACTL"; then return; fi

  # Infinite restart loop to handle suspend/resume
  while true; do
    # pactl subscribe gives us real-time audio events
    # This will block until audio events occur, or exit if pipe breaks
    "$PACTL" subscribe 2>/dev/null | while read -r line; do
      # Look for sink (output device) changes
      if printf '%s' "$line" | $GREP -qi "sink"; then
        # Send signal to main process for immediate update
        kill -SIGUSR1 "$main_pid" 2>/dev/null || exit 0
      fi
    done

    # If we get here, pactl subscribe exited (likely due to suspend/resume)
    # Wait a bit before restarting to avoid tight restart loop
    sleep 2

    # Check if main process still exists before restarting
    if ! kill -0 "$main_pid" 2>/dev/null; then
      exit 0
    fi
  done
}

# -----------------------------
# Battery (AC + level + icon)
# Only shown if battery hardware exists
# -----------------------------
battery_part() {
  # Skip if no battery hardware
  if [ "$HAS_BATTERY" = "no" ]; then
    return
  fi

  local dir ac cap stat online glyph
  dir=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1 || true)
  ac=$(ls -d /sys/class/power_supply/AC* /sys/class/power_supply/ACAD* 2>/dev/null | head -n1 || true)
  if [ -z "${dir:-}" ] || [ ! -r "$dir/capacity" ]; then
    use_icons && printf " n/a" || printf "Bat: n/a"
    return
  fi
  cap=$(cat "$dir/capacity" 2>/dev/null || echo 0)
  stat=$(cat "$dir/status" 2>/dev/null || echo Unknown)

  if [ -n "${ac:-}" ] && [ -r "$ac/online" ]; then
    online=$(cat "$ac/online" 2>/dev/null || echo 0)
  else
    online=0
    [ "$stat" = "Charging" ] && online=1
  fi

  # Choose a battery glyph by level
  local lvl=$cap
  if [ "$lvl" -ge 95 ]; then
    glyph=$(echo -ne '\uf240')
  elif [ "$lvl" -ge 75 ]; then
    glyph=$(echo -ne '\uf241')
  elif [ "$lvl" -ge 55 ]; then
    glyph=$(echo -ne '\uf242')
  elif [ "$lvl" -ge 35 ]; then
    glyph=$(echo -ne '\uf243')
  else
    glyph=$(echo -ne '\uf244')
  fi

  if [ "$online" = "1" ] || [ "$stat" = "Charging" ]; then
    use_icons && printf "%s %s%%" "$(icon_plug)" "$cap" || printf "Bat+: %s%%" "$cap"
  else
    use_icons && printf "%s %s%%" "$glyph" "$cap" || printf "Bat: %s%%" "$cap"
  fi
}

# -----------------------------
# CPU Temperature
# -----------------------------
temp_part() {
  local temp_file temp_c
  # Find first thermal zone
  temp_file=$(ls /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -n1 || true)
  if [ -z "$temp_file" ] || [ ! -r "$temp_file" ]; then
    use_icons && printf " n/a" || printf "Temp: n/a"
    return
  fi
  temp_c=$(($(cat "$temp_file" 2>/dev/null || echo 0) / 1000))
  if [ "$temp_c" -ge "$TEMP_WARN" ]; then
    use_icons && printf "%s %s°C" "$(icon_fire)" "$temp_c" || printf "Temp!: %s°C" "$temp_c"
  else
    use_icons && printf "%s %s°C" "$(icon_temp)" "$temp_c" || printf "Temp: %s°C" "$temp_c"
  fi
}

# -----------------------------
# Wi-Fi SSID with signal strength
# Only shown if WiFi hardware exists
# -----------------------------
ssid_part() {
  # Skip if no WiFi hardware
  if [ "$HAS_WIFI" = "no" ]; then
    return
  fi

  local ssid signal
  # Try nmcli first (active connection)
  if has_bin "$NMCLI"; then
    ssid=$("$NMCLI" -t -f NAME connection show --active 2>/dev/null |
      $GREP -v '^lo$' | $GREP -v 'docker' | head -n1 | trim || true)

    # Get signal strength if we have an active WiFi connection
    if [ -n "${ssid:-}" ]; then
      # Get the active WiFi device
      local wifi_dev
      wifi_dev=$("$NMCLI" -t -f DEVICE,TYPE device status 2>/dev/null |
        $GREP ':wifi$' | head -n1 | cut -d: -f1 || true)

      if [ -n "${wifi_dev:-}" ]; then
        # Get signal strength (0-100)
        signal=$("$NMCLI" -f IN-USE,SIGNAL device wifi list 2>/dev/null |
          $GREP '^\*' | $AWK '{print $2}' || true)
      fi
    fi
  fi

  # Fall back to iwgetid for SSID if nmcli didn't work
  if [ -z "${ssid:-}" ] && has_bin "$IWGETID"; then
    ssid=$("$IWGETID" -r 2>/dev/null | trim || true)
  fi

  # Fall back to iw for signal strength if we don't have it yet
  if [ -z "${signal:-}" ] && [ -n "${ssid:-}" ] && has_bin "$IW"; then
    local wifi_dev
    wifi_dev=$(ls /sys/class/net/wl* 2>/dev/null | head -n1 | xargs basename || true)
    if [ -n "${wifi_dev:-}" ]; then
      # Get signal in dBm and convert to approximate percentage
      local dbm
      dbm=$("$IW" dev "$wifi_dev" link 2>/dev/null |
        $GREP 'signal:' | $AWK '{print $2}' || true)
      if [ -n "${dbm:-}" ]; then
        # Convert dBm to percentage (roughly: -30dBm=100%, -90dBm=0%)
        signal=$($AWK -v d="$dbm" 'BEGIN{
          if (d >= -30) print 100
          else if (d <= -90) print 0
          else printf("%d", (d + 90) * 100 / 60)
        }')
      fi
    fi
  fi

  # Display result
  if [ -z "${ssid:-}" ]; then
    use_icons && printf "%s n/a" "$(icon_wifi)" || printf "WiFi: n/a"
  elif [ -n "${signal:-}" ] && [ "$signal" -gt 0 ] 2>/dev/null; then
    use_icons && printf "%s %s %s%%" "$(icon_wifi)" "$ssid" "$signal" || printf "WiFi: %s %s%%" "$ssid" "$signal"
  else
    use_icons && printf "%s %s" "$(icon_wifi)" "$ssid" || printf "WiFi: %s" "$ssid"
  fi
}

# -----------------------------
# Bluetooth (connected devices)
# Only shown if Bluetooth hardware exists
# -----------------------------
bluetooth_part() {
  # Skip if no Bluetooth hardware
  if [ "$HAS_BLUETOOTH" = "no" ]; then
    return
  fi

  if ! has_bin "$BLUETOOTHCTL"; then
    use_icons && printf "%s n/a" "$(icon_bt)" || printf "BT: n/a"
    return
  fi
  local devices
  devices=$("$BLUETOOTHCTL" devices Connected 2>/dev/null | wc -l)
  if [ "$devices" -gt 0 ]; then
    use_icons && printf "%s %s" "$(icon_bt)" "$devices" || printf "BT: %s" "$devices"
  else
    use_icons && printf "%s off" "$(icon_bt)" || printf "BT: off"
  fi
}

# -----------------------------
# Music (what's playing via playerctl)
# Only shown if music is playing
# -----------------------------
music_part() {
  if ! has_bin "$PLAYERCTL"; then
    return # Don't show anything if playerctl not available
  fi
  local status title artist out
  # Get playback status (Playing/Paused/Stopped)
  status=$("$PLAYERCTL" status 2>/dev/null || true)
  if [ "$status" != "Playing" ]; then
    return # Don't show anything if not playing
  fi
  # Get track info
  title=$("$PLAYERCTL" metadata title 2>/dev/null | trim || true)
  artist=$("$PLAYERCTL" metadata artist 2>/dev/null | trim || true)
  if [ -z "$title" ]; then
    return # No track info available
  fi
  # Build output (truncate if too long)
  if [ -n "$artist" ]; then
    out="$artist - $title"
  else
    out="$title"
  fi
  # Truncate to reasonable length
  if [ ${#out} -gt 40 ]; then
    out="${out:0:37}..."
  fi
  use_icons && printf "%s %s" "$(icon_music)" "$out" || printf "Music: %s" "$out"
}

# -----------------------------
# Nextcloud sync status
# Checks if Nextcloud client is running and syncing
# Always shown (placed next to WiFi when WiFi hardware exists)
# -----------------------------
nextcloud_part() {
  local state="offline"
  local nc_pid nc_log last_line

  # Check if Nextcloud client is running
  nc_pid=$(pgrep -x nextcloud 2>/dev/null | head -n1 || true)

  if [ -n "$nc_pid" ]; then
    # Client is running - check sync status from log
    nc_log="$HOME/.local/share/Nextcloud/logs/nextcloud.log"

    if [ -f "$nc_log" ] && [ -r "$nc_log" ]; then
      # Get last 50 lines and check for sync activity
      last_line=$(tail -n 50 "$nc_log" 2>/dev/null | $GREP -i "sync\|upload\|download" | tail -n1 || true)

      if [ -n "$last_line" ]; then
        # Check if sync is active (within last 2 minutes)
        if echo "$last_line" | $GREP -qi "starting\|running\|progress"; then
          state="syncing"
        else
          state="online"
        fi
      else
        # No recent sync activity in log, assume online
        state="online"
      fi
    else
      # Log file not found or not readable, but client is running
      state="online"
    fi
  fi

  if use_icons; then
    case "$state" in
    offline) printf "%s offline" "$(icon_cloud_off)" ;;
    syncing) printf "%s syncing" "$(icon_cloud_sync)" ;;
    *) printf "%s online" "$(icon_cloud)" ;;
    esac
  else
    case "$state" in
    offline) printf "NC: offline" ;;
    syncing) printf "NC: syncing" ;;
    *) printf "NC: online" ;;
    esac
  fi
}

# -----------------------------
# System updates available
# Caches result to avoid slow checkupdates on every refresh
# Only shown if updates are available
# -----------------------------
UPDATES_CACHE_FILE="/tmp/dwm-status-updates-$USER"
UPDATES_CACHE_TIME=0

updates_part() {
  # Find checkupdates dynamically (handles different install locations)
  local checkupdates_bin
  checkupdates_bin=$(command -v checkupdates 2>/dev/null)

  if [ -z "$checkupdates_bin" ]; then
    return # checkupdates not available
  fi

  local now count
  now=$(date +%s)

  # Check if cache is still valid
  if [ -f "$UPDATES_CACHE_FILE" ] && [ "${UPDATES_CACHE_TIME:-0}" -gt 0 ]; then
    local cache_age=$((now - UPDATES_CACHE_TIME))
    if [ "$cache_age" -lt "$UPDATES_CACHE" ]; then
      count=$(cat "$UPDATES_CACHE_FILE" 2>/dev/null || echo 0)
    fi
  fi

  # Refresh cache if needed
  if [ -z "${count:-}" ]; then
    count=$("$checkupdates_bin" 2>/dev/null | wc -l || echo 0)
    count=${count:-0}                    # Ensure it's a number
    count=$(echo "$count" | tr -d ' \n') # Remove whitespace

    # Also check AUR if yay is available
    if has_cmd yay; then
      local aur_count
      aur_count=$(yay -Qua 2>/dev/null | wc -l || echo 0)
      aur_count=${aur_count:-0}                    # Ensure it's a number
      aur_count=$(echo "$aur_count" | tr -d ' \n') # Remove whitespace
      count=$((count + aur_count))
    fi

    echo "$count" >"$UPDATES_CACHE_FILE"
    UPDATES_CACHE_TIME=$now
  fi

  # Only show if there are updates
  if [ "$count" -gt 0 ]; then
    use_icons && printf "%s %s" "$(icon_updates)" "$count" || printf "Upd: %s" "$count"
  fi
}

# -----------------------------
# Disk usage warning
# Only shown if usage exceeds threshold
# -----------------------------
disk_part() {
  if ! has_bin "$DF"; then
    return # Don't show anything if df not available
  fi

  local usage
  # Get root filesystem usage percentage (without % sign)
  usage=$("$DF" -h / 2>/dev/null | "$AWK" 'NR==2 {print $5}' | "$SED" 's/%//' || echo 0)

  # Only show if above warning threshold
  if [ "$usage" -ge "$((100 - DISK_WARN))" ]; then
    local free_pct=$((100 - usage))
    use_icons && printf "%s Disk: %s%%" "$(icon_disk)" "$free_pct" || printf "Disk!: %s%%" "$free_pct"
  fi
}

# -----------------------------
# Clipboard history
# Shows icon with optional counters for activity
# Format: 📋 (no activity), 📋 3 (3 text clips), 📋 5/2 (5 text + 2 screenshots)
# -----------------------------
clipboard_part() {
  local text_count=0
  local screenshot_count=0

  # Count text clips (max 5 entries due to clip-save.sh trimming)
  if [ -f "$HOME/.cache/clip-text.log" ]; then
    text_count=$(wc -l <"$HOME/.cache/clip-text.log" 2>/dev/null || echo 0)
  fi

  # Count screenshots from last 24 hours
  # Use -L to follow symlinks (handles ~/Pictures/Screenshots -> ~/Nextcloud/Screenshots)
  if [ -d "$HOME/Pictures/Screenshots" ]; then
    screenshot_count=$(find -L "$HOME/Pictures/Screenshots" -maxdepth 1 -type f -name "*.png" -mtime -1 2>/dev/null | wc -l)
  fi

  # Display format based on activity
  if [ "$text_count" -eq 0 ] && [ "$screenshot_count" -eq 0 ]; then
    # No activity
    use_icons && printf "%s" "$(icon_clip)" || printf "CLIP"
  elif [ "$screenshot_count" -eq 0 ]; then
    # Only text clips
    use_icons && printf "%s %d" "$(icon_clip)" "$text_count" || printf "CLIP: %d" "$text_count"
  else
    # Both text and screenshots
    use_icons && printf "%s %d/%d" "$(icon_clip)" "$text_count" "$screenshot_count" || printf "CLIP: %d/%d" "$text_count" "$screenshot_count"
  fi
}

# -----------------------------
# Date / Time
# -----------------------------
date_part() { "$DATE" +"%Y-%m-%d w:%V"; }
time_part() { "$DATE" +"%H:%M"; }

# -----------------------------
# Assemble the bar line
# -----------------------------
build_line() {
  local parts=()
  local battery wifi bluetooth music updates disk

  # Clipboard (always first)
  parts+=("$(clipboard_part)")

  # Always visible parts
  parts+=("$(volume_part)")

  # Battery (only if hardware exists)
  battery=$(battery_part)
  [ -n "$battery" ] && parts+=("$battery")

  parts+=("$(temp_part)")

  # WiFi (only if hardware exists)
  wifi=$(ssid_part)
  [ -n "$wifi" ] && parts+=("$wifi")

  # Nextcloud (always shown, placed next to WiFi when WiFi exists)
  parts+=("$(nextcloud_part)")

  # Bluetooth (only if hardware exists)
  bluetooth=$(bluetooth_part)
  [ -n "$bluetooth" ] && parts+=("$bluetooth")

  # Conditional parts (only shown when relevant)
  music=$(music_part)
  [ -n "$music" ] && parts+=("$music")

  updates=$(updates_part)
  [ -n "$updates" ] && parts+=("$updates")

  disk=$(disk_part)
  [ -n "$disk" ] && parts+=("$disk")

  parts+=("$(date_part)" "$(time_part)")

  # Join with separator
  local line="${parts[0]:-}"
  local i
  for i in "${parts[@]:1}"; do
    line+="$(icon_sep)${i}"
  done
  printf "[ %s ]" "$line"
}

# -----------------------------
# Wait for network before starting the main loop
# (Prevents 'n/a' at boot when NetworkManager isn't ready yet.)
# -----------------------------
wait_for_wifi() {
  # Skip waiting if no WiFi hardware
  if [ "$HAS_WIFI" = "no" ]; then
    return 0
  fi

  local tries=0 max=30
  if ! has_bin "$NMCLI"; then return 0; fi
  while ! "$NMCLI" -t -f STATE g 2>/dev/null | $GREP -q '^connected'; do
    sleep 1
    tries=$((tries + 1))
    [ $tries -ge $max ] && break # fail open after ~30s
  done
}

# -----------------------------
# Cleanup function
# -----------------------------
cleanup() {
  # Kill volume listener if it's running
  if [ -n "${VOLUME_LISTENER_PID:-}" ]; then
    kill "$VOLUME_LISTENER_PID" 2>/dev/null || true
  fi
  exit 0
}

trap cleanup EXIT INT TERM

# -----------------------------
# Main
# -----------------------------
# Detect hardware at startup
detect_hardware

wait_for_wifi

# Start volume listener in background
volume_listener $$ &
VOLUME_LISTENER_PID=$!

# Main loop with suspend/resume detection
INTERVAL=${DWM_STATUS_INTERVAL:-10}
LOOP_COUNT=0
LAST_UPDATE=$(date +%s)

while :; do
  NOW=$(date +%s)

  # Detect time jump (suspend/resume or NTP adjustment)
  # If more than 2*INTERVAL seconds passed, we likely resumed from suspend
  TIME_DIFF=$((NOW - LAST_UPDATE))
  if [ $TIME_DIFF -gt $((INTERVAL * 2)) ]; then
    # System was suspended - update immediately
    FORCE_UPDATE=1
  fi

  # Update the bar
  "$XSETROOT" -name "$(build_line)"
  LAST_UPDATE=$NOW

  # Reset force update flag after use
  if [ $FORCE_UPDATE -eq 1 ]; then
    FORCE_UPDATE=0
  fi

  # Sleep with timeout using 'read' command which is interruptible
  # This allows SIGUSR1 to interrupt the sleep for immediate volume updates
  read -t $INTERVAL <> <(:) 2>/dev/null || true

  # Check if we got a signal for immediate update during sleep
  if [ $FORCE_UPDATE -eq 1 ]; then
    continue # Skip to next iteration immediately
  fi

  # Every ~5 minutes, check if volume listener is still alive and restart if needed
  LOOP_COUNT=$((LOOP_COUNT + 1))
  if [ $((LOOP_COUNT % 30)) -eq 0 ]; then
    if [ -n "${VOLUME_LISTENER_PID:-}" ]; then
      if ! kill -0 "$VOLUME_LISTENER_PID" 2>/dev/null; then
        # Volume listener died, restart it
        volume_listener $$ &
        VOLUME_LISTENER_PID=$!
      fi
    fi
  fi
done
