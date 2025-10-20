#!/usr/bin/env bash
# DWM status bar for Arch Linux
# ------------------------------------------------------------
# Shows (left → right): VOLUME | BATTERY | WIFI-SSID | NEXTCLOUD | DATE | TIME
# The bar is resilient: each part tolerates missing tools and falls back to "n/a".
#
# Design goals:
# - Robust on multiple Arch installs (different PATHs/backends).
# - No racing at boot: waits for NetworkManager to be "connected".
# - SSID via ACTIVE connection (nmcli), not via scan list.
# - Minimal dependencies; graceful degradation.
#
# Environment variables (optional):
#   DWM_STATUS_ICONS=1        # 1 = use icons when possible (default), 0 = text-only
#   DWM_STATUS_ASSUME_ICONS=0 # 1 = force icons even if unsure
#   DWM_STATUS_INTERVAL=10    # refresh interval (seconds)
#   DWM_STATUS_WIFI_CMD=iwgetid|nmcli  # force SSID source
#   DWM_STATUS_NET_PING=1.1.1.1        # ping target for connectivity (default 1.1.1.1)

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
GREP="/usr/bin/grep"
SED="/usr/bin/sed"

# Ensure a sane PATH for any sub-processes (keeps user overrides last)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# -----------------------------
# Helpers
# -----------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; } # PATH-based check
has_bin() { [ -x "$1" ]; }                     # absolute-path check
trim() { $SED 's/^[[:space:]]\+//;s/[[:space:]]\+$//'; }

# -----------------------------
# Icon / text mode
# -----------------------------
ICONS=${DWM_STATUS_ICONS:-1}
ASSUME=${DWM_STATUS_ASSUME_ICONS:-0}

use_icons() {
  # If you KNOW you run a Nerd Font in the bar, set ASSUME=1 to always use icons.
  if [ "$ASSUME" = "1" ]; then return 0; fi
  [ "$ICONS" = "1" ] && return 0 || return 1
}

# -----------------------------
# Glyphs (Nerd Font). Text fallbacks are used in each part function.
# -----------------------------
icon_bat() { printf ''; }        # battery default (level-specific used below)
icon_plug() { printf ''; }       # AC/charging
icon_wifi() { printf ''; }       # Wi-Fi
icon_cloud() { printf ''; }      # Nextcloud online
icon_cloud_sync() { printf '󰓦'; } # Nextcloud syncing
icon_cloud_off() { printf '󰅛'; }  # Nextcloud offline
icon_spk() { printf ''; }        # volume
icon_spk_mute() { printf '󰝟'; }   # clearer mute icon
icon_sep() { printf ' | '; }      # separator

# -----------------------------
# Volume (PipeWire via wpctl)
# -----------------------------
volume_part() {
  if ! has_bin "$WPCTL"; then
    use_icons && printf " n/a" || printf "Vol: n/a"
    return
  fi
  local line mute vol pct
  line=$("$WPCTL" get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
  # Typical outputs:
  #  "Volume: 0.34 [0.00, 1.00]"
  #  "Volume: 0.34 [0.00, 1.00] MUTE"
  #  "Volume: 0.34 [0.00, 1.00] Mute: true"
  mute=$(printf '%s\n' "$line" | $GREP -Eoi '(MUTE|Mute:\s*true)' | head -n1 || true)
  vol=$(printf '%s\n' "$line" | $AWK '/Volume:/ {print $2}')
  if [ -z "${vol:-}" ]; then
    use_icons && printf " n/a" || printf "Vol: n/a"
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
# Battery (AC + level + icon)
# -----------------------------
battery_part() {
  local dir ac cap stat online glyph
  dir=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1 || true)
  ac=$(ls -d /sys/class/power_supply/AC* /sys/class/power_supply/ACAD* 2>/dev/null | head -n1 || true)
  if [ -z "${dir:-}" ] || [ ! -r "$dir/capacity" ]; then
    use_icons && printf " n/a" || printf "Bat: n/a"
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
    glyph=''
  elif [ "$lvl" -ge 75 ]; then
    glyph=''
  elif [ "$lvl" -ge 55 ]; then
    glyph=''
  elif [ "$lvl" -ge 35 ]; then
    glyph=''
  else glyph=''; fi

  if [ "$online" = "1" ] || [ "$stat" = "Charging" ]; then
    use_icons && printf "%s %s%%" "$(icon_plug)" "$cap" || printf "Bat+: %s%%" "$cap"
  else
    use_icons && printf "%s %s%%" "$glyph" "$cap" || printf "Bat: %s%%" "$cap"
  fi
}

# -----------------------------
# Wi-Fi SSID (nmcli active connection → iwgetid → iw)
# Uses absolute paths and retries a few times for early-boot races.
# -----------------------------
ssid_part() {
  local ssid="" forced=${DWM_STATUS_WIFI_CMD:-}
  local tries

  # 1) nmcli: read the active Wi-Fi connection (not the scan list)
  if [ -z "$ssid" ] && has_bin "$NMCLI" && { [ -z "${forced:-}" ] || [ "$forced" = "nmcli" ]; }; then
    for tries in 1 2 3; do
      ssid=$("$NMCLI" -t -f NAME,TYPE connection show --active |
        "$AWK" -F: '$2=="802-11-wireless"{print $1; exit}')
      [ -n "$ssid" ] && break
      sleep 1
    done
  fi

  # 2) iwgetid: simple fallback (needs wireless_tools)
  if [ -z "$ssid" ] && [ "${forced:-}" = "iwgetid" ] && has_bin "$IWGETID"; then
    ssid=$("$IWGETID" -r 2>/dev/null || true)
  elif [ -z "$ssid" ] && has_bin "$IWGETID" && [ -z "${forced:-}" ]; then
    ssid=$("$IWGETID" -r 2>/dev/null || true)
  fi

  # 3) iw: last resort (if installed)
  if [ -z "$ssid" ] && has_bin "$IW"; then
    local dev
    dev=$("$IW" dev | "$AWK" '/Interface/ {print $2; exit}')
    if [ -n "$dev" ]; then
      ssid=$("$IW" dev "$dev" link 2>/dev/null | $SED -n 's/^[[:space:]]*SSID: //p')
    fi
  fi

  [ -z "$ssid" ] && ssid="n/a"
  use_icons && printf "%s %s" "$(icon_wifi)" "$ssid" || printf "Net: %s" "$ssid"
}

# -----------------------------
# Internet (quick connectivity test)
# -----------------------------
net_online() {
  local host=${DWM_STATUS_NET_PING:-1.1.1.1}
  "$PING" -n -q -W 1 -c 1 "$host" >/dev/null 2>&1
}

# -----------------------------
# Nextcloud status (CLI → D-Bus heuristic → fallback)
# -----------------------------
nextcloud_part() {
  local state="online"
  if ! net_online; then
    state="offline"
  else
    if has_cmd nextcloud; then
      local s
      s=$(nextcloud --status 2>/dev/null || true)
      if printf '%s' "$s" | $GREP -Eiq '(sync(ing)?|busy|indexing|scanning|transferring)'; then
        state="syncing"
      elif printf '%s' "$s" | $GREP -Eiq '(disconnected|offline)'; then
        # Internet looks fine but client claims offline → still show "online"
        state="online"
      fi
    else
      # Heuristic via qdbus (optional)
      if has_cmd qdbus && qdbus | $GREP -q "org.nextcloud"; then
        local bus
        bus=$(qdbus | $GREP org.nextcloud | head -n1 || true)
        if [ -n "$bus" ] && qdbus "$bus" 2>/dev/null | $GREP -iq "Transfer"; then
          state="syncing"
        fi
      fi
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
# Date / Time
# -----------------------------
date_part() { "$DATE" +"%Y-%m-%d w:%V"; }
time_part() { "$DATE" +"%H:%M"; }

# -----------------------------
# Assemble the bar line
# -----------------------------
build_line() {
  local parts=()
  parts+=("$(volume_part)")
  parts+=("$(battery_part)")
  parts+=("$(ssid_part)")
  parts+=("$(nextcloud_part)")
  parts+=("$(date_part)" "$(time_part)")

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
  local tries=0 max=30
  if ! has_bin "$NMCLI"; then return 0; fi
  while ! "$NMCLI" -t -f STATE g 2>/dev/null | $GREP -q '^connected'; do
    sleep 1
    tries=$((tries + 1))
    [ $tries -ge $max ] && break # fail open after ~30s
  done
}

# -----------------------------
# Main loop
# -----------------------------
wait_for_wifi
INTERVAL=${DWM_STATUS_INTERVAL:-10}
while :; do
  "$XSETROOT" -name "$(build_line)"
  sleep "$INTERVAL"
done
