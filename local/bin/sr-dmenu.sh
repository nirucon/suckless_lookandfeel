#!/usr/bin/env bash
# Sveriges Radio – dmenu-klient (endast livekanaler)
# Beroenden: bash, curl, jq, mpv, dmenu  (valfritt: notify-send)
# Testad på Linux/X11 (dmenu). Fungerar även med rofi -dmenu om du byter DMENU.

set -euo pipefail

# ---- Konfig ----
SR_API_BASE="https://api.sr.se/api/v2"
UA="sr-dmenu/1.0 (+https://api.sr.se/)"

DMENU_CMD=${DMENU_CMD:-"dmenu -i -l 15"}
PROMPT() { ${DMENU_CMD} -p "$1"; }

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sr-dmenu"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sr-dmenu"
mkdir -p "$CACHE_DIR" "$STATE_DIR"

MPV_PID_FILE="$STATE_DIR/mpv.pid"
MPV_STATE_FILE="$STATE_DIR/mpv.state" # "playing" / "paused"
NOWPLAY_FILE="$STATE_DIR/nowplaying.txt"
CHANNEL_CACHE_FILE="$CACHE_DIR/channels.json"

# ---- Hjälp ----
has() { command -v "$1" >/dev/null 2>&1; }
die() {
  printf "Fel: %s\n" "$1" >&2
  exit 1
}

# Kravkoll
for bin in curl jq mpv; do
  has "$bin" || die "Saknar beroende: $bin"
done

info() {
  local msg="$1"
  if has notify-send; then
    notify-send -u normal -t 2000 -a "Sveriges Radio" "$msg" || true
  else
    printf '[INFO] %s\n' "$msg"
  fi
}

# ---- MPV ----
mpv_running() {
  [[ -f "$MPV_PID_FILE" ]] || return 1
  local mpid
  mpid="$(cat "$MPV_PID_FILE" 2>/dev/null || true)"
  [[ -n "${mpid:-}" ]] && ps -p "$mpid" >/dev/null 2>&1
}
stop_playback() {
  if mpv_running; then kill "$(cat "$MPV_PID_FILE")" || true; fi
  rm -f "$MPV_PID_FILE" "$MPV_STATE_FILE" "$NOWPLAY_FILE"
}
toggle_pause() {
  if mpv_running; then
    local mpid
    mpid="$(cat "$MPV_PID_FILE")"
    if [[ -f "$MPV_STATE_FILE" && "$(cat "$MPV_STATE_FILE")" == "paused" ]]; then
      kill -CONT "$mpid" 2>/dev/null || true
      echo "playing" >"$MPV_STATE_FILE"
      info "Fortsätter uppspelning"
    else
      kill -STOP "$mpid" 2>/dev/null || true
      echo "paused" >"$MPV_STATE_FILE"
      info "Pausad"
    fi
  else
    info "Ingen uppspelning igång."
  fi
}

play_url() {
  local title="$1" url="$2"
  stop_playback
  echo "$title" >"$NOWPLAY_FILE"
  (
    nohup mpv --force-window=no --no-video --really-quiet --title="SR: $title" "$url" \
      >/dev/null 2>&1 &
    echo $! >"$MPV_PID_FILE"
  ) &
  disown || true
  echo "playing" >"$MPV_STATE_FILE"
  info "Spelar: $title"
}

# ---- HTTP ----
_fetch() {
  curl -fsSL -A "$UA" --retry 2 --retry-delay 0 --connect-timeout 5 --max-time 20 "$1"
}

# ---- Livekanaler (med cache) ----
load_channels() {
  # Ladda cache om yngre än 12 h
  if [[ -f "$CHANNEL_CACHE_FILE" ]]; then
    local mtime age
    if stat -f %m "$CHANNEL_CACHE_FILE" >/dev/null 2>&1; then
      mtime="$(stat -f %m "$CHANNEL_CACHE_FILE")"
    else
      mtime="$(stat -c %Y "$CHANNEL_CACHE_FILE")"
    fi
    age=$(($(date +%s) - mtime))
    if ((age < 43200)); then return 0; fi
  fi

  local out ok=1
  if ! out="$(_fetch "$SR_API_BASE/channels?format=json&pagination=false&size=500")"; then ok=0; fi
  if [[ $ok -eq 1 ]] && ! printf '%s' "$out" | jq -e '.channels | type=="array"' >/dev/null 2>&1; then ok=0; fi
  if [[ $ok -eq 1 ]]; then
    printf '%s' "$out" >"$CHANNEL_CACHE_FILE"
  else
    : # lämna ev. gammal cache
  fi
}

list_channels() {
  load_channels
  jq -r '.channels[]
    | select(.liveaudio.url!=null)
    | "[LIVE] \(.name) — \(.id)"' "$CHANNEL_CACHE_FILE"
}

get_channel_live_url() {
  local id="$1"
  _fetch "$SR_API_BASE/channels/$id?format=json" | jq -r '.channel.liveaudio.url // empty'
}

# ---- dmenu helpers ----
pick_from_list() {
  PROMPT "${1:-Välj}" </dev/stdin
}

ask_text() {
  PROMPT "${1:-Text}"
}

extract_last_id() {
  sed 's/.*— \([^ ]\+\)$/\1/; s/.*- \([^ ]\+\)$/\1/'
}

# ---- Menyer ----
main_menu() {
  cat <<'EOF' | PROMPT "SR"
Lyssna på livekanal
Paus/Fortsätt
Stoppa
Visa nu spelas
Avsluta
EOF
}

do_live() {
  local sel id url
  sel="$(list_channels | pick_from_list "Livekanal")" || return 0
  [[ -n "${sel:-}" ]] || return 0
  id="$(printf '%s' "$sel" | extract_last_id)"
  url="$(get_channel_live_url "$id")"
  [[ -n "$url" ]] || {
    info "Kunde inte hämta stream-URL."
    return 0
  }
  play_url "$sel" "$url"
}

show_nowplaying() {
  if [[ -f "$NOWPLAY_FILE" ]] && mpv_running; then
    sed -n '1p' "$NOWPLAY_FILE" | PROMPT "Nu spelas"
  else
    printf 'Inget spelas just nu.\n' | PROMPT "Nu spelas"
  fi
}

# ---- Huvudloop ----
while :; do
  choice="$(main_menu || true)"
  case "${choice:-}" in
  "Lyssna på livekanal") do_live ;;
  "Paus/Fortsätt") toggle_pause ;;
  "Stoppa")
    stop_playback
    info "Stoppad."
    ;;
  "Visa nu spelas") show_nowplaying ;;
  "" | "Avsluta") exit 0 ;;
  *) exit 0 ;;
  esac
done
