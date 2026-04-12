#!/usr/bin/env bash
set -u

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

XSETROOT="/usr/bin/xsetroot"
DATEBIN="/usr/bin/date"
HOSTNAMEBIN="/usr/bin/hostname"
NMCLI="/usr/bin/nmcli"
CHECKUPDATES="/usr/bin/checkupdates"
FREEBIN="/usr/bin/free"
UPTIMEBIN="/usr/bin/uptime"

INTERVAL=2
TEMP_WARN=70
UPDATES_CACHE_SECONDS=1800
MEDIA_CACHE_SECONDS=300
DISK_WARN_PERCENT=90

SHOW_MEDIA=1
SHOW_VOLUME=1
SHOW_MEMORY=0
SHOW_UPTIME=0
SHOW_UPDATES=1
SHOW_TEMP=1
SHOW_BATTERY=1
SHOW_NETWORK=1
SHOW_DISK=0
SHOW_CPU=0
SHOW_LOAD=0
SHOW_BLUETOOTH=0
USE_ICONS=1

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dwm-status"
UPDATES_FILE="$CACHE_DIR/updates.count"
UPDATES_STAMP="$CACHE_DIR/updates.stamp"
MEDIA_CACHE_FILE="$CACHE_DIR/media.count"
MEDIA_CACHE_STAMP="$CACHE_DIR/media.stamp"

mkdir -p "$CACHE_DIR"

icon_music() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '' || printf 'm'
}

icon_photos() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '' || printf 'p'
}

icon_videos() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '' || printf 'v'
}

icon_volume() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '' || printf 'vol'
}

icon_volume_mute() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰝟' || printf 'vol'
}

icon_wifi() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '' || printf 'wifi'
}

icon_net() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰈀' || printf 'net'
}

icon_updates() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰏗' || printf 'upd'
}

icon_temp() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '' || printf 'temp'
}

icon_memory() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰍛' || printf 'mem'
}

icon_uptime() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰅐' || printf 'up'
}

icon_disk() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰋊' || printf 'disk'
}

icon_cpu() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰻠' || printf 'cpu'
}

icon_load() {
  [[ "$USE_ICONS" -eq 1 ]] && printf '󰓅' || printf 'load'
}

icon_battery_for_level() {
  local level="$1"
  local charging="${2:-0}"

  if [[ "$USE_ICONS" -ne 1 ]]; then
    if [[ "$charging" -eq 1 ]]; then
      printf 'bat+'
    else
      printf 'bat'
    fi
    return 0
  fi

  if [[ "$charging" -eq 1 ]]; then
    if (( level >= 95 )); then printf '󰂅'
    elif (( level >= 90 )); then printf '󰂋'
    elif (( level >= 80 )); then printf '󰂊'
    elif (( level >= 70 )); then printf '󰢞'
    elif (( level >= 60 )); then printf '󰂉'
    elif (( level >= 50 )); then printf '󰢝'
    elif (( level >= 40 )); then printf '󰂈'
    elif (( level >= 30 )); then printf '󰂇'
    elif (( level >= 20 )); then printf '󰂆'
    else printf '󰢜'
    fi
  else
    if (( level >= 95 )); then printf '󰁹'
    elif (( level >= 90 )); then printf '󰂂'
    elif (( level >= 80 )); then printf '󰂁'
    elif (( level >= 70 )); then printf '󰂀'
    elif (( level >= 60 )); then printf '󰁿'
    elif (( level >= 50 )); then printf '󰁾'
    elif (( level >= 40 )); then printf '󰁽'
    elif (( level >= 30 )); then printf '󰁼'
    elif (( level >= 20 )); then printf '󰁻'
    elif (( level >= 10 )); then printf '󰁺'
    else printf '󰂎'
    fi
  fi
}

get_kernel() {
  local k short
  k="$(uname -r 2>/dev/null)"
  short="$(printf '%s' "$k" | cut -d- -f1)"

  case "$k" in
    *cachyos*) printf '%s-cachy' "$short" ;;
    *arch*) printf '%s-arch' "$short" ;;
    *) printf '%s' "$short" ;;
  esac
}

get_hostname() {
  "$HOSTNAMEBIN" 2>/dev/null || printf 'host?'
}

get_network() {
  [[ "$SHOW_NETWORK" -eq 1 ]] || return 0
  [[ -x "$NMCLI" ]] || return 0

  local eth wifi_name wifi_signal

  eth="$("$NMCLI" -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
    | awk -F: '$2=="ethernet" && $3=="connected" {print $1; exit}')"

  if [[ -n "${eth:-}" ]]; then
    printf '%s online' "$(icon_net)"
    return 0
  fi

  wifi_name="$("$NMCLI" -t -f IN-USE,SSID,SIGNAL device wifi list 2>/dev/null \
    | awk -F: '$1=="*" {print $2; exit}')"

  wifi_signal="$("$NMCLI" -t -f IN-USE,SSID,SIGNAL device wifi list 2>/dev/null \
    | awk -F: '$1=="*" {print $3; exit}')"

  if [[ -n "${wifi_name:-}" ]]; then
    if [[ -n "${wifi_signal:-}" ]]; then
      printf '%s %s %s%%' "$(icon_wifi)" "$wifi_name" "$wifi_signal"
    else
      printf '%s %s' "$(icon_wifi)" "$wifi_name"
    fi
    return 0
  fi

  printf '%s offline' "$(icon_net)"
}

get_battery() {
  [[ "$SHOW_BATTERY" -eq 1 ]] || return 0

  local bat cap status icon charging=0

  bat="$(
    for d in /sys/class/power_supply/*; do
      [[ -d "$d" ]] || continue
      [[ -r "$d/type" ]] || continue
      if grep -qx 'Battery' "$d/type" 2>/dev/null; then
        printf '%s\n' "$d"
        break
      fi
    done
  )"

  [[ -n "${bat:-}" ]] || return 0
  [[ -r "$bat/capacity" ]] || return 0

  cap="$(tr -d '[:space:]' < "$bat/capacity" 2>/dev/null)"
  [[ "$cap" =~ ^[0-9]+$ ]] || return 0

  status=""
  [[ -r "$bat/status" ]] && status="$(tr -d '[:space:]' < "$bat/status" 2>/dev/null)"

  case "$status" in
    Charging|Full) charging=1 ;;
    *) charging=0 ;;
  esac

  icon="$(icon_battery_for_level "$cap" "$charging")"

  if [[ "$status" == "Full" ]]; then
    printf '%s %s%% full' "$icon" "$cap"
  else
    printf '%s %s%%' "$icon" "$cap"
  fi
}

get_temp_high() {
  [[ "$SHOW_TEMP" -eq 1 ]] || return 0

  local best=0 file raw temp_c
  while IFS= read -r file; do
    [[ -r "$file" ]] || continue
    raw="$(tr -d '[:space:]' < "$file" 2>/dev/null)"
    [[ "$raw" =~ ^[0-9]+$ ]] || continue
    temp_c=$((raw / 1000))
    (( temp_c > best )) && best="$temp_c"
  done < <(find /sys/class/thermal -type f -name temp 2>/dev/null)

  (( best > 0 )) || return 0

  if [[ "$best" -ge "$TEMP_WARN" ]]; then
    printf '%s %sC' "$(icon_temp)" "$best"
  fi
}

get_memory() {
  [[ "$SHOW_MEMORY" -eq 1 ]] || return 0
  [[ -x "$FREEBIN" ]] || return 0

  local used total pct
  read -r used total < <("$FREEBIN" -m 2>/dev/null | awk '/^Mem:/ {print $3, $2}')
  [[ -n "${used:-}" && -n "${total:-}" && "$total" -gt 0 ]] || return 0

  pct=$(( used * 100 / total ))
  printf '%s %s%%' "$(icon_memory)" "$pct"
}

get_uptime() {
  [[ "$SHOW_UPTIME" -eq 1 ]] || return 0
  [[ -x "$UPTIMEBIN" ]] || return 0

  local up
  up="$("$UPTIMEBIN" -p 2>/dev/null | sed 's/^up //')"
  [[ -n "${up:-}" ]] || return 0
  printf '%s %s' "$(icon_uptime)" "$up"
}

get_updates() {
  [[ "$SHOW_UPDATES" -eq 1 ]] || return 0
  [[ -x "$CHECKUPDATES" ]] || return 0

  local now stamp age pac_count aur_count total
  now="$("$DATEBIN" +%s 2>/dev/null || printf '0')"
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
    elif command -v yay >/dev/null 2>&1; then
      aur_count="$(yay -Qua 2>/dev/null | wc -l | tr -d '[:space:]')"
      aur_count="${aur_count:-0}"
    fi

    total=$((pac_count + aur_count))

    printf '%s\n' "$total" > "$UPDATES_FILE" 2>/dev/null || true
    printf '%s\n' "$now" > "$UPDATES_STAMP" 2>/dev/null || true
  fi

  if [[ "${total:-0}" -gt 0 ]]; then
    printf '%s %s' "$(icon_updates)" "$total"
  fi
}

get_volume() {
  [[ "$SHOW_VOLUME" -eq 1 ]] || return 0

  if command -v wpctl >/dev/null 2>&1; then
    local out vol
    out="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)" || return 0

    if printf '%s' "$out" | grep -q 'MUTED'; then
      printf '%s mute' "$(icon_volume_mute)"
      return 0
    fi

    vol="$(printf '%s\n' "$out" | awk '{print int($2 * 100)}')"
    printf '%s %s%%' "$(icon_volume)" "${vol:-0}"
    return 0
  fi

  if command -v amixer >/dev/null 2>&1; then
    local amix level
    amix="$(amixer get Master 2>/dev/null)"
    [[ -n "${amix:-}" ]] || return 0

    if printf '%s' "$amix" | grep -q '\[off\]'; then
      printf '%s mute' "$(icon_volume_mute)"
      return 0
    fi

    level="$(printf '%s\n' "$amix" | awk -F'[][]' '/%/ {print $2; exit}')"
    [[ -n "${level:-}" ]] && printf '%s %s' "$(icon_volume)" "$level"
    return 0
  fi
}

pick_first_existing_dir() {
  local dir
  for dir in "$@"; do
    [[ -d "$dir" ]] && {
      printf '%s' "$dir"
      return 0
    }
  done
  return 1
}

get_media_paths() {
  local music_dir photos_dir videos_dir

  music_dir="$(pick_first_existing_dir \
    "$HOME/Music" \
    "$HOME/mp3" \
    "$HOME/media/Music")"

  photos_dir="$(pick_first_existing_dir \
    "$HOME/Pictures" \
    "$HOME/Photos" \
    "$HOME/media/Pictures")"

  videos_dir="$(pick_first_existing_dir \
    "$HOME/Videos" \
    "$HOME/media/Videos")"

  printf '%s\n%s\n%s\n' \
    "${music_dir:-}" \
    "${photos_dir:-}" \
    "${videos_dir:-}"
}

count_files_in_dir() {
  local dir="$1"
  shift || true

  [[ -n "${dir:-}" ]] || {
    printf '0'
    return 0
  }

  [[ -e "$dir" ]] || {
    printf '0'
    return 0
  }

  find -L "$dir" -type f \( "$@" \) 2>/dev/null | wc -l | tr -d '[:space:]'
}

get_media_counts() {
  [[ "$SHOW_MEDIA" -eq 1 ]] || return 0

  local now stamp age media_line
  now="$("$DATEBIN" +%s 2>/dev/null || printf '0')"
  stamp=0

  if [[ -r "$MEDIA_CACHE_STAMP" ]]; then
    stamp="$(tr -d '[:space:]' < "$MEDIA_CACHE_STAMP" 2>/dev/null)"
    stamp="${stamp:-0}"
  fi

  age=$((now - stamp))

  if [[ -r "$MEDIA_CACHE_FILE" && "$age" -lt "$MEDIA_CACHE_SECONDS" ]]; then
    cat "$MEDIA_CACHE_FILE"
    return 0
  fi

  local music_dir photos_dir videos_dir
  local mp3_count photo_count video_count
  local -a media_paths=()

  mapfile -t media_paths < <(get_media_paths)
  music_dir="${media_paths[0]:-}"
  photos_dir="${media_paths[1]:-}"
  videos_dir="${media_paths[2]:-}"

  mp3_count="$(count_files_in_dir "$music_dir" \
    -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.opus")"

  photo_count="$(count_files_in_dir "$photos_dir" \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.avif")"

  video_count="$(count_files_in_dir "$videos_dir" \
    -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.webm" -o -iname "*.m4v")"

  media_line="$(icon_music) ${mp3_count:-0} $(icon_photos) ${photo_count:-0} $(icon_videos) ${video_count:-0}"

  printf '%s\n' "$media_line" > "$MEDIA_CACHE_FILE" 2>/dev/null || true
  printf '%s\n' "$now" > "$MEDIA_CACHE_STAMP" 2>/dev/null || true

  printf '%s' "$media_line"
}

get_disk() {
  [[ "$SHOW_DISK" -eq 1 ]] || return 0

  local percent mountpoint
  mountpoint="${1:-/}"

  percent="$(df -P "$mountpoint" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')"
  [[ "$percent" =~ ^[0-9]+$ ]] || return 0

  if (( percent >= DISK_WARN_PERCENT )); then
    printf '%s %s%%' "$(icon_disk)" "$percent"
  else
    printf '%s %s%%' "$(icon_disk)" "$percent"
  fi
}

get_cpu() {
  [[ "$SHOW_CPU" -eq 1 ]] || return 0
  return 0
}

get_load() {
  [[ "$SHOW_LOAD" -eq 1 ]] || return 0

  local load
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
  [[ -n "${load:-}" ]] || return 0

  printf '%s %s' "$(icon_load)" "$load"
}

get_bluetooth() {
  [[ "$SHOW_BLUETOOTH" -eq 1 ]] || return 0
  return 0
}

build_status_line() {
  local kernel host network battery temp updates media volume memory uptime disk cpu load bluetooth datepart timepart
  local -a parts=()

  kernel="$(get_kernel)"
  host="$(get_hostname)"
  network="$(get_network || true)"
  battery="$(get_battery || true)"
  temp="$(get_temp_high || true)"
  updates="$(get_updates || true)"
  media="$(get_media_counts || true)"
  volume="$(get_volume || true)"
  memory="$(get_memory || true)"
  uptime="$(get_uptime || true)"
  disk="$(get_disk || true)"
  cpu="$(get_cpu || true)"
  load="$(get_load || true)"
  bluetooth="$(get_bluetooth || true)"
  datepart="$("$DATEBIN" '+%Y-%m-%d w%V')"
  timepart="$("$DATEBIN" '+%H:%M')"

  [[ -n "${media:-}" ]] && parts+=("$media")
  [[ -n "${volume:-}" ]] && parts+=("$volume")
  [[ -n "${network:-}" ]] && parts+=("$network")
  [[ -n "${battery:-}" ]] && parts+=("$battery")
  [[ -n "${temp:-}" ]] && parts+=("$temp")
  [[ -n "${memory:-}" ]] && parts+=("$memory")
  [[ -n "${uptime:-}" ]] && parts+=("$uptime")
  [[ -n "${disk:-}" ]] && parts+=("$disk")
  [[ -n "${cpu:-}" ]] && parts+=("$cpu")
  [[ -n "${load:-}" ]] && parts+=("$load")
  [[ -n "${bluetooth:-}" ]] && parts+=("$bluetooth")
  [[ -n "${updates:-}" ]] && parts+=("$updates")

  parts+=("$kernel" "$host" "$datepart" "$timepart")

  printf '[ %s ]' "$(printf '%s\n' "${parts[@]}" | paste -sd '|' - | sed 's/|/ | /g')"
}

while :; do
  line="$(build_status_line)"
  "$XSETROOT" -name "$line" 2>/dev/null || true
  sleep "$INTERVAL"
done
