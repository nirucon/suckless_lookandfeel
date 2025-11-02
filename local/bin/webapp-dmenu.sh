#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Linux WebApp Builder — dmenu-friendly edition
# - Works perfectly with dmenu (no TTY prompts needed in --dmenu mode)
# - Manual creation (name + URL [+ optional icon]), or batch-create categories
# - Creates: ~/.local/bin/<app_id>, ~/.local/share/applications/<app_id>.desktop
# - Optional isolated profile per app (Chrome/Chromium/Brave --user-data-dir)
# - Duplicate handling via --overwrite=[ask|yes|no] (ask=default in --dmenu)
# - NEW: If run with *no arguments*, it auto-starts in dmenu mode.
# =============================================================================

# ---------- Config ----------
DMENU_MODE=0
OVERWRITE_POLICY="ask"       # ask|yes|no
SEPARATE_PROFILE_DEFAULT="n" # default for batch creation
BROWSER_PREF=(brave brave-browser google-chrome-stable chromium)

# ---------- Minimal helpers (dmenu-safe; no colors) ----------
say() { printf "%b\n" "$*"; }
info() { say "[*] $*"; }
ok() { say "[OK] $*"; }
warn() { say "[!] $*"; }
err() { say "[X] $*"; }

# ---------- dmenu wrappers ----------
have_dmenu() { command -v dmenu >/dev/null 2>&1; }
dmenu_ask() {
  # usage: prompt default
  local prompt="$1"
  shift
  local def="${1:-}"
  shift || true
  if have_dmenu; then
    printf "%s" "$def" | dmenu -p "$prompt"
  else
    read -r -p "$prompt " REPLY || true
    printf "%s" "$REPLY"
  fi
}
dmenu_menu() {
  # usage: prompt "Item 1" "Item 2" ...
  local prompt="$1"
  shift
  if have_dmenu; then
    printf "%s\n" "$@" | dmenu -p "$prompt"
  else
    local i=1
    for it in "$@"; do
      printf "%d) %s\n" "$i" "$it"
      ((i++))
    done
    read -r -p "$prompt " sel || true
    case "$sel" in
    1) printf "%s" "$1" ;;
    2) printf "%s" "$2" ;;
    3) printf "%s" "$3" ;;
    4) printf "%s" "$4" ;;
    *) printf "" ;;
    esac
  fi
}

# ---------- Browser detection ----------
detect_browser() {
  local b=""
  for c in "${BROWSER_PREF[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then
      b="$c"
      break
    fi
  done
  printf '%s' "$b"
}

# ---------- Make safe id ----------
make_safe_id() {
  local raw="$1"
  local id
  id="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  [[ -z "$id" ]] && id="webapp"
  [[ "$id" =~ ^[a-z] ]] || id="x${id}"
  printf '%s' "$id"
}

# ---------- Icon install (optional) ----------
install_icon_size() {
  local size="$1" src="$2" name="$3"
  xdg-icon-resource install --context apps --size "$size" "$src" "$name" >/dev/null
}

fetch_and_install_icon() {
  local ICON_URL="$1" ICON_NAME="$2"
  [[ -z "$ICON_URL" ]] && return 0
  command -v curl >/dev/null 2>&1 || {
    warn "curl missing; skipping icon."
    return 0
  }

  local TMP_ICON
  TMP_ICON="$(mktemp -t webapp_icon_XXXXXX)"
  if ! curl -fsSL "$ICON_URL" -o "$TMP_ICON"; then
    warn "Failed to download icon: $ICON_URL"
    rm -f "$TMP_ICON"
    return 0
  fi

  local FILETYPE
  FILETYPE="$(file -b --mime-type "$TMP_ICON" || true)"
  if [[ "$FILETYPE" == "image/svg+xml" && -x "$(command -v rsvg-convert)" ]]; then
    for s in 16 24 32 48 64 96 128 256 512; do
      local TMP_RESIZED
      TMP_RESIZED="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
      rsvg-convert -w "$s" -h "$s" -o "$TMP_RESIZED" "$TMP_ICON"
      install_icon_size "$s" "$TMP_RESIZED" "$ICON_NAME"
      rm -f "$TMP_RESIZED"
    done
  elif [[ "$FILETYPE" == "image/png" && -x "$(command -v convert)" ]]; then
    for s in 16 24 32 48 64 96 128 256 512; do
      local TMP_RESIZED
      TMP_RESIZED="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
      convert "$TMP_ICON" -resize "${s}x${s}" "$TMP_RESIZED"
      install_icon_size "$s" "$TMP_RESIZED" "$ICON_NAME"
      rm -f "$TMP_RESIZED"
    done
  else
    install_icon_size 512 "$TMP_ICON" "$ICON_NAME" || true
  fi
  rm -f "$TMP_ICON"
}

# ---------- Core creation ----------
create_webapp_core() {
  # Args: name url separate[y|n] icon_url
  local APP_NAME="$1" APP_URL="$2" SEP="${3:-n}" ICON_URL="${4:-}"
  [[ -z "$APP_NAME" || -z "$APP_URL" ]] && {
    err "name and url are required"
    return 1
  }

  local APP_SAFE_ID
  APP_SAFE_ID="$(make_safe_id "$APP_NAME")"
  local LOCAL_BIN="$HOME/.local/bin"
  local APP_APPS_DIR="$HOME/.local/share/applications"
  local APP_BIN="$LOCAL_BIN/${APP_SAFE_ID}"
  local DESKTOP_FILE="$APP_APPS_DIR/${APP_SAFE_ID}.desktop"
  local ICON_NAME="${APP_SAFE_ID}"
  local PROFILE_DIR="$HOME/.local/share/webapps/${APP_SAFE_ID}"
  local BROWSER_BIN
  BROWSER_BIN="$(detect_browser)"

  mkdir -p "$LOCAL_BIN" "$APP_APPS_DIR" "$HOME/.local/share/webapps"

  # Duplicate handling
  if [[ -e "$APP_BIN" || -e "$DESKTOP_FILE" ]]; then
    case "$OVERWRITE_POLICY" in
    yes) : ;;
    no)
      info "Exists; skipping: $APP_NAME"
      return 0
      ;;
    ask)
      local ans
      if ((DMENU_MODE)); then
        ans="$(dmenu_menu "Overwrite ${APP_NAME}?" "Yes" "No")"
      else
        read -r -p "Overwrite '${APP_NAME}'? (y/n): " ans || true
      fi
      [[ "${ans,,}" =~ ^(y|yes)$ || "$ans" == "Yes" ]] || {
        info "Skipped ${APP_NAME}"
        return 0
      }
      ;;
    esac
  fi

  # Optional icon
  fetch_and_install_icon "$ICON_URL" "$ICON_NAME" || true

  # Launcher
  cat >"$APP_BIN" <<LAUNCH
#!/usr/bin/env bash
set -euo pipefail
BROWSER_BIN="${BROWSER_BIN}"
APP_URL="$(printf '%s' "$APP_URL")"
APP_ID="${APP_SAFE_ID}"
PROFILE_DIR="\$HOME/.local/share/webapps/\${APP_ID}"
CLASS="WebApp-\${APP_ID}"

ARGS=( --class="\$CLASS" --app="\$APP_URL" )
if [[ "${SEP,,}" == "y" ]]; then
  mkdir -p "\$PROFILE_DIR"
  ARGS+=( --user-data-dir="\$PROFILE_DIR" --profile-directory=Default )
fi

if [[ -n "\$BROWSER_BIN" ]]; then
  exec "\$BROWSER_BIN" "\${ARGS[@]}" >/dev/null 2>&1 &
else
  echo "No supported browser found (brave/chromium/google-chrome-stable)." >&2
  exit 127
fi
LAUNCH
  chmod +x "$APP_BIN"

  # Desktop entry
  {
    echo "[Desktop Entry]"
    echo "Name=${APP_NAME}"
    echo "Comment=WebApp for ${APP_URL}"
    echo "Exec=${APP_BIN}"
    echo "Terminal=false"
    echo "Type=Application"
    echo "Icon=${ICON_NAME}"
    echo "Categories=Network;"
    echo "StartupWMClass=WebApp-${APP_SAFE_ID}"
  } >"$DESKTOP_FILE"

  ok "Created/updated: ${APP_NAME}"
}

# ---------- Presets ----------
declare -a CATEGORY_WORK=(
  "Microsoft Teams|https://teams.microsoft.com/"
  "Microsoft OneNote|https://m365.cloud.microsoft/launch/OneNote/"
  "Microsoft SharePoint|https://uddevalla.sharepoint.com/"
  "Microsoft Outlook|https://outlook.office.com/mail"
  "Microsoft Calendar|https://outlook.office.com/calendar/view/workweek"
  "Microsoft Loop|https://loop.cloud.microsoft/"
  "Microsoft OneDrive|https://uddevalla-my.sharepoint.com"
  "Microsoft Planner|https://planner.cloud.microsoft/"
  "Microsoft Copilot (AI)|https://m365.cloud.microsoft/chat/"
  "Microsoft PowerPoint|https://powerpoint.cloud.microsoft/"
  "Microsoft Word|https://word.cloud.microsoft/"
  "Microsoft Excel|https://excel.cloud.microsoft"
  "Microsoft Lists|https://uddevalla-my.sharepoint.com/personal/nicklas_rudolfsson_uddevalla_se1/_layouts/15/Lists.aspx"
  "Microsoft Power Automate|https://make.powerautomate.com/"
  "Microsoft Stream|https://m365.cloud.microsoft/launch/Stream/"
  "Microsoft Visio|https://m365.cloud.microsoft/launch/Visio/"
  "Microsoft To Do|https://to-do.office.com/"
  "Microsoft Whiteboard|https://whiteboard.cloud.microsoft/"
  "Microsoft Copilot Studio|https://copilotstudio.microsoft.com/"
  "Microsoft Bookings|https://outlook.office.com/bookings/homepage"
  "Microsoft People|https://outlook.office.com/people"
  "Microsoft Insights|https://insights.cloud.microsoft"
  "Microsoft Forms|https://forms.office.com"
  "Inblicken|https://inblicken.uddevalla.se/"
  "Medvind|https://uddevalla.medvind.visma.com/MvWeb/"
  "Raindance|https://raindance.uddevalla.se/raindance/SSO/Saml"
  "Uddevalla.se|https://uddevalla.se"
)

declare -a CATEGORY_PRIVATE=(
  "ChatGPT (AI)|https://chatgpt.com/"
  "GrokAI (AI)|https://x.ai/"
  "Google Gemini (AI)|https://gemini.google.com/"
  "Google Gmail|https://mail.google.com/"
  "Google Calendar|https://calendar.google.com/"
  "Google Drive|https://drive.google.com/"
  "Facebook|https://www.facebook.com/"
  "Instagram|https://www.instagram.com/"
  "Claude (AI)|https://claude.ai/"
  "Jellyfin|http://100.108.23.65:8096/"
  "DeepSeek (AI)|https://chat.deepseek.com/"
)

batch_create_category() {
  local category_name="$1"
  shift
  local -n items="$1"
  local count=0
  for entry in "${items[@]}"; do
    local name="${entry%%|*}"
    local url="${entry#*|}"
    create_webapp_core "$name" "$url" "$SEPARATE_PROFILE_DEFAULT" ""
    ((count++)) || true
  done
  ok "Category '${category_name}': ${count} shortcuts processed."
}

# ---------- CLI & dmenu modes ----------
usage() {
  cat <<USAGE
Usage:
  $0 --create-manual --name "App Name" --url "https://example.com" [--icon-url URL] [--separate y|n] [--overwrite ask|yes|no]
  $0 --create-category work|private [--overwrite ask|yes|no]
  $0 --dmenu [--overwrite ask|yes|no]

Notes:
  If you launch *without arguments* (e.g., from dmenu by typing the script name),
  it will automatically run in dmenu mode.
USAGE
}

parse_args() {
  local mode=""
  local name="" url="" icon_url="" separate="n" category=""

  # Auto-enter dmenu mode if launched with no args
  if (($# == 0)); then
    DMENU_MODE=1
    dmenu_flow
    exit 0
  fi

  while (($#)); do
    case "$1" in
    --create-manual) mode="manual" ;;
    --create-category)
      mode="category"
      category="${2:-}"
      shift
      ;;
    --name)
      name="${2:-}"
      shift
      ;;
    --url)
      url="${2:-}"
      shift
      ;;
    --icon-url)
      icon_url="${2:-}"
      shift
      ;;
    --separate)
      separate="${2:-n}"
      shift
      ;;
    --overwrite)
      OVERWRITE_POLICY="${2:-ask}"
      shift
      ;;
    --dmenu)
      DMENU_MODE=1
      mode="dmenu"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      err "Unknown arg: $1"
      usage
      exit 2
      ;;
    esac
    shift || true
  done

  case "$mode" in
  manual)
    [[ -n "$name" && -n "$url" ]] || {
      err "manual mode requires --name and --url"
      exit 2
    }
    create_webapp_core "$name" "$url" "$separate" "$icon_url"
    ;;
  category)
    case "${category,,}" in
    work) batch_create_category "Work" CATEGORY_WORK ;;
    private) batch_create_category "Private" CATEGORY_PRIVATE ;;
    *)
      err "Unknown category: $category (use work|private)"
      exit 2
      ;;
    esac
    ;;
  dmenu)
    ((DMENU_MODE)) || DMENU_MODE=1
    dmenu_flow
    ;;
  *)
    usage
    exit 2
    ;;
  esac
}

dmenu_flow() {
  local choice
  choice="$(dmenu_menu "WebApp Builder" "Create manual" "Create all Work" "Create all Private" "Exit")"
  case "$choice" in
  "Create manual")
    local name url icon sep
    name="$(dmenu_ask "App name:" "")"
    [[ -n "$name" ]] || {
      warn "No name. Aborted."
      return 0
    }
    url="$(dmenu_ask "App URL:" "")"
    [[ -n "$url" ]] || {
      warn "No URL. Aborted."
      return 0
    }
    icon="$(dmenu_ask "Icon URL (optional):" "")"
    sep="$(dmenu_menu "Separate browser profile?" "No" "Yes")"
    [[ "$sep" == "Yes" ]] && sep="y" || sep="n"
    create_webapp_core "$name" "$url" "$sep" "$icon"
    ;;
  "Create all Work")
    batch_create_category "Work" CATEGORY_WORK
    ;;
  "Create all Private")
    batch_create_category "Private" CATEGORY_PRIVATE
    ;;
  *)
    :
    ;;
  esac
}

# ---------- Entry ----------
main() {
  parse_args "$@"
}

main "$@"
