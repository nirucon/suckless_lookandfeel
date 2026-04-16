#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Linux WebApp Builder — Helium-first edition
#
# Features:
# - dmenu-friendly, works without TTY prompts in --dmenu mode
# - Helium is first browser choice by default
# - Manual creation or batch-create categories
# - Creates:
#     ~/.local/bin/<app_id>
#     ~/.local/share/applications/<app_id>.desktop
# - Optional isolated profile per app (--separate y|n)
# - Duplicate handling via --overwrite ask|yes|no
# - Supports browser selection:
#     --browser auto|helium|brave|chromium|chrome|default
# - Supports open mode:
#     --open-mode app|normal
#     app    = Chromium-style --app mode
#     normal = open URL as a regular browser window/tab
# - If run with no arguments, auto-starts in dmenu mode
# =============================================================================

# ---------- Config ----------
DMENU_MODE=0
OVERWRITE_POLICY="ask"        # ask|yes|no
SEPARATE_PROFILE_DEFAULT="n"  # default for batch creation
DEFAULT_BROWSER_MODE="auto"   # auto|helium|brave|chromium|chrome|default
DEFAULT_OPEN_MODE="app"       # app|normal

BROWSER_PREF=(helium-browser brave brave-browser google-chrome-stable chromium)

# ---------- Minimal helpers ----------
say()  { printf "%b\n" "$*"; }
info() { say "[*] $*"; }
ok()   { say "[OK] $*"; }
warn() { say "[!] $*"; }
err()  { say "[X] $*"; }

# ---------- dmenu wrappers ----------
have_dmenu() { command -v dmenu >/dev/null 2>&1; }

dmenu_ask() {
  local prompt="$1"
  local def="${2:-}"
  if have_dmenu; then
    printf "%s" "$def" | dmenu -p "$prompt"
  else
    local reply=""
    read -r -p "$prompt " reply || true
    printf "%s" "$reply"
  fi
}

dmenu_menu() {
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
    local sel=""
    read -r -p "$prompt " sel || true
    case "$sel" in
      1) printf "%s" "${1:-}" ;;
      2) printf "%s" "${2:-}" ;;
      3) printf "%s" "${3:-}" ;;
      4) printf "%s" "${4:-}" ;;
      5) printf "%s" "${5:-}" ;;
      *) printf "" ;;
    esac
  fi
}

# ---------- Validation ----------
validate_url() {
  local url="$1"
  [[ "$url" =~ ^https?:// ]] || return 1
  return 0
}

validate_yesno() {
  local v="${1,,}"
  [[ "$v" == "y" || "$v" == "n" ]]
}

validate_overwrite_policy() {
  local v="${1,,}"
  [[ "$v" == "ask" || "$v" == "yes" || "$v" == "no" ]]
}

validate_browser_mode() {
  local v="${1,,}"
  [[ "$v" == "auto" || "$v" == "helium" || "$v" == "brave" || "$v" == "chromium" || "$v" == "chrome" || "$v" == "default" ]]
}

validate_open_mode() {
  local v="${1,,}"
  [[ "$v" == "app" || "$v" == "normal" ]]
}

# ---------- Browser detection ----------
detect_browser_auto() {
  local b=""
  for c in "${BROWSER_PREF[@]}"; do
    if command -v "$c" >/dev/null 2>&1; then
      b="$c"
      break
    fi
  done
  printf '%s' "$b"
}

resolve_browser_bin() {
  local mode="${1,,}"

  case "$mode" in
    auto)
      detect_browser_auto
      ;;
    helium)
      command -v helium-browser >/dev/null 2>&1 && printf '%s' "helium-browser" || printf ''
      ;;
    brave)
      if command -v brave >/dev/null 2>&1; then
        printf '%s' "brave"
      elif command -v brave-browser >/dev/null 2>&1; then
        printf '%s' "brave-browser"
      else
        printf ''
      fi
      ;;
    chromium)
      command -v chromium >/dev/null 2>&1 && printf '%s' "chromium" || printf ''
      ;;
    chrome)
      command -v google-chrome-stable >/dev/null 2>&1 && printf '%s' "google-chrome-stable" || printf ''
      ;;
    default)
      command -v xdg-open >/dev/null 2>&1 && printf '%s' "xdg-open" || printf ''
      ;;
    *)
      printf ''
      ;;
  esac
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

# ---------- Icon install ----------
install_icon_size() {
  local size="$1" src="$2" name="$3"
  xdg-icon-resource install --context apps --size "$size" "$src" "$name" >/dev/null 2>&1 || true
}

fetch_and_install_icon() {
  local icon_url="$1"
  local icon_name="$2"

  [[ -z "$icon_url" ]] && return 0
  command -v curl >/dev/null 2>&1 || {
    warn "curl missing; skipping icon."
    return 0
  }

  local tmp_icon=""
  tmp_icon="$(mktemp -t webapp_icon_XXXXXX)"

  if ! curl -fsSL "$icon_url" -o "$tmp_icon"; then
    warn "Failed to download icon: $icon_url"
    rm -f "$tmp_icon"
    return 0
  fi

  local filetype=""
  filetype="$(file -b --mime-type "$tmp_icon" 2>/dev/null || true)"

  if [[ "$filetype" == "image/svg+xml" ]] && command -v rsvg-convert >/dev/null 2>&1; then
    for s in 16 24 32 48 64 96 128 256 512; do
      local tmp_resized=""
      tmp_resized="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
      if rsvg-convert -w "$s" -h "$s" -o "$tmp_resized" "$tmp_icon"; then
        install_icon_size "$s" "$tmp_resized" "$icon_name"
      fi
      rm -f "$tmp_resized"
    done
  elif [[ "$filetype" == "image/png" ]] && command -v convert >/dev/null 2>&1; then
    for s in 16 24 32 48 64 96 128 256 512; do
      local tmp_resized=""
      tmp_resized="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
      if convert "$tmp_icon" -resize "${s}x${s}" "$tmp_resized"; then
        install_icon_size "$s" "$tmp_resized" "$icon_name"
      fi
      rm -f "$tmp_resized"
    done
  else
    install_icon_size 512 "$tmp_icon" "$icon_name"
  fi

  rm -f "$tmp_icon"
}

# ---------- Desktop database refresh ----------
refresh_desktop_db() {
  command -v update-desktop-database >/dev/null 2>&1 || return 0
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
}

# ---------- Core creation ----------
create_webapp_core() {
  # Args:
  #   1 name
  #   2 url
  #   3 separate y|n
  #   4 icon_url
  #   5 browser_mode auto|helium|brave|chromium|chrome|default
  #   6 open_mode app|normal
  local app_name="$1"
  local app_url="$2"
  local sep="${3:-n}"
  local icon_url="${4:-}"
  local browser_mode="${5:-$DEFAULT_BROWSER_MODE}"
  local open_mode="${6:-$DEFAULT_OPEN_MODE}"

  [[ -n "$app_name" ]] || { err "App name is required"; return 1; }
  [[ -n "$app_url"  ]] || { err "App URL is required"; return 1; }

  if ! validate_url "$app_url"; then
    err "Invalid URL: must start with http:// or https://"
    return 1
  fi

  if ! validate_yesno "$sep"; then
    err "Invalid --separate value: use y or n"
    return 1
  fi

  if ! validate_browser_mode "$browser_mode"; then
    err "Invalid --browser value: use auto|helium|brave|chromium|chrome|default"
    return 1
  fi

  if ! validate_open_mode "$open_mode"; then
    err "Invalid --open-mode value: use app or normal"
    return 1
  fi

  local app_safe_id
  app_safe_id="$(make_safe_id "$app_name")"

  local local_bin="$HOME/.local/bin"
  local app_apps_dir="$HOME/.local/share/applications"
  local app_bin="$local_bin/${app_safe_id}"
  local desktop_file="$app_apps_dir/${app_safe_id}.desktop"
  local icon_name="${app_safe_id}"
  local profile_dir="$HOME/.local/share/webapps/${app_safe_id}"

  mkdir -p "$local_bin" "$app_apps_dir" "$HOME/.local/share/webapps"

  # Duplicate handling
  if [[ -e "$app_bin" || -e "$desktop_file" ]]; then
    case "$OVERWRITE_POLICY" in
      yes) : ;;
      no)
        info "Exists; skipping: $app_name"
        return 0
        ;;
      ask)
        local ans=""
        if (( DMENU_MODE )); then
          ans="$(dmenu_menu "Overwrite ${app_name}?" "Yes" "No")"
        else
          read -r -p "Overwrite '${app_name}'? (y/n): " ans || true
        fi
        [[ "${ans,,}" =~ ^(y|yes)$ || "$ans" == "Yes" ]] || {
          info "Skipped ${app_name}"
          return 0
        }
        ;;
    esac
  fi

  fetch_and_install_icon "$icon_url" "$icon_name" || true

  local resolved_browser=""
  resolved_browser="$(resolve_browser_bin "$browser_mode")"

  if [[ -z "$resolved_browser" ]]; then
    err "No supported browser found for mode: $browser_mode"
    return 1
  fi

  cat > "$app_bin" <<EOF
#!/usr/bin/env bash
set -euo pipefail

APP_NAME=$(printf '%q' "$app_name")
APP_URL=$(printf '%q' "$app_url")
APP_ID=$(printf '%q' "$app_safe_id")
PROFILE_DIR="\$HOME/.local/share/webapps/\${APP_ID}"
CLASS="WebApp-\${APP_ID}"
BROWSER_MODE=$(printf '%q' "$browser_mode")
OPEN_MODE=$(printf '%q' "$open_mode")
SEPARATE=$(printf '%q' "${sep,,}")
BROWSER_BIN=$(printf '%q' "$resolved_browser")

# Allow runtime override if wanted:
#   WEBAPP_BROWSER_MODE=helium|brave|chromium|chrome|default|auto
#   WEBAPP_OPEN_MODE=app|normal
if [[ -n "\${WEBAPP_BROWSER_MODE:-}" ]]; then
  BROWSER_MODE="\${WEBAPP_BROWSER_MODE,,}"
fi
if [[ -n "\${WEBAPP_OPEN_MODE:-}" ]]; then
  OPEN_MODE="\${WEBAPP_OPEN_MODE,,}"
fi

resolve_runtime_browser() {
  case "\$1" in
    auto)
      for c in helium-browser brave brave-browser google-chrome-stable chromium; do
        if command -v "\$c" >/dev/null 2>&1; then
          printf '%s' "\$c"
          return 0
        fi
      done
      ;;
    helium)
      command -v helium-browser >/dev/null 2>&1 && printf '%s' "helium-browser" && return 0
      ;;
    brave)
      if command -v brave >/dev/null 2>&1; then
        printf '%s' "brave"
        return 0
      elif command -v brave-browser >/dev/null 2>&1; then
        printf '%s' "brave-browser"
        return 0
      fi
      ;;
    chromium)
      command -v chromium >/dev/null 2>&1 && printf '%s' "chromium" && return 0
      ;;
    chrome)
      command -v google-chrome-stable >/dev/null 2>&1 && printf '%s' "google-chrome-stable" && return 0
      ;;
    default)
      command -v xdg-open >/dev/null 2>&1 && printf '%s' "xdg-open" && return 0
      ;;
  esac
  return 1
}

if runtime_browser="\$(resolve_runtime_browser "\$BROWSER_MODE")"; then
  BROWSER_BIN="\$runtime_browser"
fi

if [[ "\$BROWSER_MODE" == "default" || "\$BROWSER_BIN" == "xdg-open" || "\$OPEN_MODE" == "normal" ]]; then
  exec "\$BROWSER_BIN" "\$APP_URL" >/dev/null 2>&1 &
fi

ARGS=( "--class=\$CLASS" "--app=\$APP_URL" )

if [[ "\$SEPARATE" == "y" ]]; then
  mkdir -p "\$PROFILE_DIR"
  ARGS+=( "--user-data-dir=\$PROFILE_DIR" "--profile-directory=Default" )
fi

exec "\$BROWSER_BIN" "\${ARGS[@]}" >/dev/null 2>&1 &
EOF

  chmod +x "$app_bin"

  {
    echo "[Desktop Entry]"
    echo "Name=${app_name}"
    echo "Comment=WebApp for ${app_url}"
    echo "Exec=${app_bin}"
    echo "Terminal=false"
    echo "Type=Application"
    echo "Icon=${icon_name}"
    echo "Categories=Network;"
    echo "StartupWMClass=WebApp-${app_safe_id}"
  } > "$desktop_file"

  refresh_desktop_db
  ok "Created/updated: ${app_name}"
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
  local browser_mode="${2:-$DEFAULT_BROWSER_MODE}"
  local open_mode="${3:-$DEFAULT_OPEN_MODE}"

  local count=0
  for entry in "${items[@]}"; do
    local name="${entry%%|*}"
    local url="${entry#*|}"
    create_webapp_core "$name" "$url" "$SEPARATE_PROFILE_DEFAULT" "" "$browser_mode" "$open_mode"
    ((count++)) || true
  done
  ok "Category '${category_name}': ${count} shortcuts processed."
}

# ---------- Usage ----------
usage() {
  cat <<'USAGE'
Usage:
  webapp-dmenu.sh --create-manual --name "App Name" --url "https://example.com" [options]
  webapp-dmenu.sh --create-category work|private [options]
  webapp-dmenu.sh --dmenu [options]

Options:
  --name "App Name"
  --url "https://example.com"
  --icon-url URL
  --separate y|n
  --overwrite ask|yes|no
  --browser auto|helium|brave|chromium|chrome|default
  --open-mode app|normal

Examples:
  webapp-dmenu.sh --create-manual --name "Teams" --url "https://teams.microsoft.com/" --browser helium --open-mode app
  webapp-dmenu.sh --create-manual --name "Uddevalla" --url "https://uddevalla.se" --browser default --open-mode normal
  webapp-dmenu.sh --create-category work --overwrite yes
  webapp-dmenu.sh --create-category private --browser helium --overwrite yes

Notes:
  - If launched without arguments, it auto-enters dmenu mode.
  - In app mode, Chromium-style flags are used.
  - In normal/default mode, xdg-open is used.
USAGE
}

# ---------- dmenu flow ----------
dmenu_flow() {
  local choice
  choice="$(dmenu_menu "WebApp Builder" \
    "Create manual" \
    "Create all Work" \
    "Create all Private" \
    "Exit")"

  case "$choice" in
    "Create manual")
      local name url icon sep browser_mode open_mode

      name="$(dmenu_ask "App name:" "")"
      [[ -n "$name" ]] || { warn "No name. Aborted."; return 0; }

      url="$(dmenu_ask "App URL:" "")"
      [[ -n "$url" ]] || { warn "No URL. Aborted."; return 0; }

      icon="$(dmenu_ask "Icon URL (optional):" "")"

      sep="$(dmenu_menu "Separate browser profile?" "No" "Yes")"
      [[ "$sep" == "Yes" ]] && sep="y" || sep="n"

      browser_mode="$(dmenu_menu "Browser mode" "auto" "helium" "brave" "chromium" "default")"
      [[ -n "$browser_mode" ]] || browser_mode="$DEFAULT_BROWSER_MODE"

      open_mode="$(dmenu_menu "Open mode" "app" "normal")"
      [[ -n "$open_mode" ]] || open_mode="$DEFAULT_OPEN_MODE"

      create_webapp_core "$name" "$url" "$sep" "$icon" "$browser_mode" "$open_mode"
      ;;
    "Create all Work")
      batch_create_category "Work" CATEGORY_WORK "$DEFAULT_BROWSER_MODE" "$DEFAULT_OPEN_MODE"
      ;;
    "Create all Private")
      batch_create_category "Private" CATEGORY_PRIVATE "$DEFAULT_BROWSER_MODE" "$DEFAULT_OPEN_MODE"
      ;;
    *)
      :
      ;;
  esac
}

# ---------- CLI parsing ----------
parse_args() {
  local mode=""
  local name="" url="" icon_url="" separate="n" category=""
  local browser_mode="$DEFAULT_BROWSER_MODE"
  local open_mode="$DEFAULT_OPEN_MODE"

  if (($# == 0)); then
    DMENU_MODE=1
    dmenu_flow
    exit 0
  fi

  while (($#)); do
    case "$1" in
      --create-manual)
        mode="manual"
        ;;
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
      --browser)
        browser_mode="${2:-$DEFAULT_BROWSER_MODE}"
        shift
        ;;
      --open-mode)
        open_mode="${2:-$DEFAULT_OPEN_MODE}"
        shift
        ;;
      --dmenu)
        DMENU_MODE=1
        mode="dmenu"
        ;;
      -h|--help)
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

  if ! validate_overwrite_policy "$OVERWRITE_POLICY"; then
    err "Invalid --overwrite value: use ask|yes|no"
    exit 2
  fi

  if ! validate_browser_mode "$browser_mode"; then
    err "Invalid --browser value: use auto|helium|brave|chromium|chrome|default"
    exit 2
  fi

  if ! validate_open_mode "$open_mode"; then
    err "Invalid --open-mode value: use app or normal"
    exit 2
  fi

  case "$mode" in
    manual)
      [[ -n "$name" && -n "$url" ]] || {
        err "manual mode requires --name and --url"
        exit 2
      }
      create_webapp_core "$name" "$url" "$separate" "$icon_url" "$browser_mode" "$open_mode"
      ;;
    category)
      case "${category,,}" in
        work)
          batch_create_category "Work" CATEGORY_WORK "$browser_mode" "$open_mode"
          ;;
        private)
          batch_create_category "Private" CATEGORY_PRIVATE "$browser_mode" "$open_mode"
          ;;
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

main() {
  parse_args "$@"
}

main "$@"
