#!/usr/bin/env bash
set -u

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

XSETROOT="/usr/bin/xsetroot"
DATEBIN="/usr/bin/date"
UNAME="/usr/bin/uname"
HOSTNAMEBIN="/usr/bin/hostname"
NMCLI="/usr/bin/nmcli"
CHECKUPDATES="/usr/bin/checkupdates"

INTERVAL=15
TEMP_WARN=70
UPDATES_CACHE_SECONDS=1800

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dwm-status"
UPDATES_FILE="$CACHE_DIR/updates.count"
UPDATES_STAMP="$CACHE_DIR/updates.stamp"

mkdir -p "$CACHE_DIR"

get_kernel() {
  local k
  k="$(uname -r 2>/dev/null)"

  # Korta ner till version + distro-tag
  case "$k" in
    *cachyos*)
      printf '%s-cachy' "$(printf '%s' "$k" | cut -d- -f1)"
      ;;
    *arch*)
      printf '%s-arch' "$(printf '%s' "$k" | cut -d- -f1)"
      ;;
    *)
      printf '%s' "$(printf '%s' "$k" | cut -d- -f1)"
      ;;
  esac
}

get_hostname() {
  "$HOSTNAMEBIN" 2>/dev/null || echo "host?"
}

get_network() {
  if [[ -x "$NMCLI" ]]; then
    local eth wifi_name wifi_signal

    eth=$("$NMCLI" -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
      | awk -F: '$2=="ethernet" && $3=="connected" {print $1; exit}')

    if [[ -n "${eth:-}" ]]; then
      printf 'online'
      return
    fi

    wifi_name=$("$NMCLI" -t -f IN-USE,SSID,SIGNAL device wifi list 2>/dev/null \
      | awk -F: '$1=="*" {print $2; exit}')

    wifi_signal=$("$NMCLI" -t -f IN-USE,SSID,SIGNAL device wifi list 2>/dev/null \
      | awk -F: '$1=="*" {print $3; exit}')

    if [[ -n "${wifi_name:-}" ]]; then
      if [[ -n "${wifi_signal:-}" ]]; then
        printf 'wifi: %s (%s%%)' "$wifi_name" "$wifi_signal"
      else
        printf 'wifi: %s' "$wifi_name"
      fi
      return
    fi
  fi

  printf 'offline'
}

get_battery() {
  local bat cap
  bat="$(find /sys/class/power_supply -maxdepth 1 -type d -name 'BAT*' 2>/dev/null | head -n1)"

  [[ -n "${bat:-}" ]] || return 0
  [[ -r "$bat/capacity" ]] || return 0

  cap="$(tr -d '[:space:]' < "$bat/capacity" 2>/dev/null)"
  [[ -n "${cap:-}" ]] || return 0

  printf 'bat %s%%' "$cap"
}

get_temp_high() {
  local temp_file temp_raw temp_c
  temp_file="$(find /sys/class/thermal -type f -name temp 2>/dev/null | head -n1)"

  [[ -n "${temp_file:-}" ]] || return 0
  [[ -r "$temp_file" ]] || return 0

  temp_raw="$(tr -d '[:space:]' < "$temp_file" 2>/dev/null)"
  [[ -n "${temp_raw:-}" ]] || return 0

  temp_c=$((temp_raw / 1000))

  if [[ "$temp_c" -ge "$TEMP_WARN" ]]; then
    printf 'temp %sC' "$temp_c"
  fi
}

get_updates() {
  [[ -x "$CHECKUPDATES" ]] || return 0

  local now stamp age pac_count aur_count total
  now="$("$DATEBIN" +%s 2>/dev/null || echo 0)"
  stamp=0

  if [[ -r "$UPDATES_STAMP" ]]; then
    stamp="$(tr -d '[:space:]' < "$UPDATES_STAMP" 2>/dev/null)"
    stamp="${stamp:-0}"
  fi

  age=$((now - stamp))

  if [[ -r "$UPDATES_FILE" && "$age" -lt "$UPDATES_CACHE_SECONDS" ]]; then
    total="$(tr -d '[:space:]' < "$UPDATES_FILE" 2>/dev/null)"
    total="${total:-0}"
  else
    pac_count="$("$CHECKUPDATES" 2>/dev/null | wc -l | tr -d '[:space:]')"
    pac_count="${pac_count:-0}"

    aur_count=0
    if command -v paru >/dev/null 2>&1; then
      aur_count="$(paru -Qua 2>/dev/null | wc -l | tr -d '[:space:]')"
      aur_count="${aur_count:-0}"
    fi

    total=$((pac_count + aur_count))

    printf '%s\n' "$total" > "$UPDATES_FILE" 2>/dev/null || true
    printf '%s\n' "$now" > "$UPDATES_STAMP" 2>/dev/null || true
  fi

  if [[ "${total:-0}" -gt 0 ]]; then
    printf 'upd %s' "$total"
  fi
}

while :; do
  kernel="$(get_kernel)"
  host="$(get_hostname)"
  network="$(get_network)"
  battery="$(get_battery || true)"
  temp="$(get_temp_high || true)"
  updates="$(get_updates || true)"
  datepart="$("$DATEBIN" '+%Y-%m-%d w%V')"
  timepart="$("$DATEBIN" '+%H:%M')"

  parts=("$kernel" "$host" "$network")

  [[ -n "${battery:-}" ]] && parts+=("$battery")
  [[ -n "${temp:-}" ]] && parts+=("$temp")
  [[ -n "${updates:-}" ]] && parts+=("$updates")

  parts+=("$datepart" "$timepart")

  line="[ $(printf '%s\n' "${parts[@]}" | paste -sd '|' - | sed 's/|/ | /g') ]"

  "$XSETROOT" -name "$line" 2>/dev/null || true
  sleep "$INTERVAL"
done
