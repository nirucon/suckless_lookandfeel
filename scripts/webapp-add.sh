#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Linux WebApp Builder (Arch/Arch-based)
# - Create Chrome/Chromium/Brave "web app" shortcuts that launch with --app
# - Manual mode (pick name & URL) OR batch-create from preset categories
# - Installs icon(s) system-wide via xdg-icon-resource when an icon URL is given
# - Creates:
#     * ~/.local/bin/<app_id>            (launcher script; added to PATH-friendly place)
#     * ~/.local/share/applications/<app_id>.desktop (so rofi/drun finds it)
#     * ~/.local/share/webapps/<app_id>  (optional separate browser profile dir)
# - Safe, idempotent; re-running overwrites the launcher + .desktop cleanly
# - Extremely well-commented for easy modification
#
# NOTE: The browser itself is NOT installed by this script. Have one of:
#       brave | brave-browser | google-chrome-stable | chromium
# =============================================================================

# ---------- Pretty output helpers ----------
BOLD="$(tput bold 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
RED="$(tput setaf 1 2>/dev/null || true)"

say()  { printf "%b\n" "$*"; }
info() { say "${BLUE}[*]${RESET} $*"; }
ok()   { say "${GREEN}[✓]${RESET} $*"; }
warn() { say "${YELLOW}[!]${RESET} $*"; }
err()  { say "${RED}[✗]${RESET} $*"; }

# ---------- Environment/requirements ----------
require_arch() {
  if ! command -v pacman >/dev/null 2>&1; then
    err "This script targets Arch/Arch-based systems (requires pacman)."
    exit 1
  fi
}

ensure_requirements() {
  # Core tools used by the script
  local req=(curl xdg-user-dir xdg-icon-resource file)
  local opt=(rsvg-convert convert)  # rsvg-convert (librsvg), convert (ImageMagick) for icon resizing

  local missing=()
  for x in "${req[@]}"; do command -v "$x" >/dev/null 2>&1 || missing+=("$x"); done

  if ((${#missing[@]})); then
    info "Installing required packages: ${missing[*]}"
    if ! sudo -v; then
      err "sudo is required to auto-install dependencies."
      say "Install manually: sudo pacman -S --needed ${missing[*]}"
      exit 1
    fi
    sudo pacman -S --noconfirm --needed "${missing[@]}"
    ok "Required packages installed."
  fi

  local opt_missing=()
  for x in "${opt[@]}"; do command -v "$x" >/dev/null 2>&1 || opt_missing+=("$x"); done
  if ((${#opt_missing[@]})); then
    warn "Optional (recommended) packages missing: ${opt_missing[*]}"
    warn "They enable SVG/PNG resizing to common sizes for nicer icons."
    say  "Install anytime: sudo pacman -S --needed ${opt_missing[*]}"
  fi

  # Ensure ~/.local/bin & applications dir exist
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/webapps"
}

# ---------- Browser detection ----------
detect_browser() {
  # Keep this list ordered by your preference
  local b=""
  for c in brave brave-browser google-chrome-stable chromium; do
    if command -v "$c" >/dev/null 2>&1; then b="$c"; break; fi
  done
  if [[ -z "$b" ]]; then
    warn "No supported browser found in PATH (brave / chromium / google-chrome-stable)."
    warn "Shortcuts will still be created, but they won't launch until a supported browser is installed."
  fi
  printf '%s' "$b"
}

# ---------- Make a safe application id ----------
# Turn any human-readable name into a filesystem-safe id:
#   - lowercase
#   - remove non-alphanumerics
#   - if the first char is not a letter, prefix with 'x'
# (This fixes the previous bug where every id got an 'x' prefix due to a sed pattern.)
make_safe_id() {
  local raw="$1"
  local id
  id="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  [[ -z "$id" ]] && id="webapp"
  if [[ ! "$id" =~ ^[a-z] ]]; then
    id="x${id}"
  fi
  printf '%s' "$id"
}

# ---------- Install an icon into the user's icon theme cache ----------
install_icon_size() {
  local size="$1" src="$2" name="$3"
  # xdg-icon-resource installs into ~/.local/share/icons/...
  xdg-icon-resource install --context apps --size "$size" "$src" "$name" >/dev/null
}

# ---------- Core: create one webapp from parameters ----------
# Args:
#   $1 = App Name   (e.g., "Microsoft Teams")
#   $2 = App URL    (e.g., "https://teams.microsoft.com/")
#   $3 = sep        ("y" to use a separate browser profile per app, else "n")
#   $4 = icon_url   (optional URL to PNG or SVG icon; pass "" to skip)
create_webapp_core() {
  local APP_NAME="$1"
  local APP_URL="$2"
  local sep="${3:-n}"
  local ICON_URL="${4:-}"

  if [[ -z "$APP_NAME" || -z "$APP_URL" ]]; then
    err "Both name and URL are required."
    return 1
  fi

  local LOCAL_BIN="$HOME/.local/bin"
  local APP_APPS_DIR="$HOME/.local/share/applications"
  local APP_SAFE_ID; APP_SAFE_ID="$(make_safe_id "$APP_NAME")"
  local APP_BIN="$LOCAL_BIN/${APP_SAFE_ID}"
  local DESKTOP_FILE="$APP_APPS_DIR/${APP_SAFE_ID}.desktop"
  local ICON_NAME="${APP_SAFE_ID}"
  local PROFILE_DIR="$HOME/.local/share/webapps/${APP_SAFE_ID}"
  mkdir -p "$PROFILE_DIR"

  local BROWSER_BIN; BROWSER_BIN="$(detect_browser)"

  # ----- Optional icon handling -----
  local ICON_SET=0
  if [[ -n "$ICON_URL" ]]; then
    local TMP_ICON; TMP_ICON="$(mktemp -t webapp_icon_XXXXXX)"
    info "Downloading icon for ${APP_NAME}…"
    if ! curl -fsSL "$ICON_URL" -o "$TMP_ICON"; then
      warn "Could not download icon. Continuing without a custom icon."
    else
      local FILETYPE; FILETYPE="$(file -b --mime-type "$TMP_ICON" || true)"
      if [[ "$FILETYPE" == "image/svg+xml" && -x "$(command -v rsvg-convert)" ]]; then
        info "Converting SVG → PNG at common sizes…"
        for s in 16 24 32 48 64 96 128 256 512; do
          local TMP_RESIZED; TMP_RESIZED="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
          rsvg-convert -w "$s" -h "$s" -o "$TMP_RESIZED" "$TMP_ICON"
          install_icon_size "$s" "$TMP_RESIZED" "$ICON_NAME"
          rm -f "$TMP_RESIZED"
        done
        ICON_SET=1
      elif [[ "$FILETYPE" == "image/png" && -x "$(command -v convert)" ]]; then
        info "Resizing PNG to common sizes…"
        for s in 16 24 32 48 64 96 128 256 512; do
          local TMP_RESIZED; TMP_RESIZED="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
          convert "$TMP_ICON" -resize "${s}x${s}" "$TMP_RESIZED"
          install_icon_size "$s" "$TMP_RESIZED" "$ICON_NAME"
          rm -f "$TMP_RESIZED"
        done
        ICON_SET=1
      else
        # Fallback: attempt to install the original at 512px if possible
        if [[ "$FILETYPE" == "image/svg+xml" && -x "$(command -v convert)" ]]; then
          local PNG_FALLBACK; PNG_FALLBACK="$(mktemp -t webapp_icon_XXXXXX).png"
          if convert "$TMP_ICON" "$PNG_FALLBACK"; then
            install_icon_size 512 "$PNG_FALLBACK" "$ICON_NAME"
            ICON_SET=1
          fi
          rm -f "$PNG_FALLBACK"
        else
          install_icon_size 512 "$TMP_ICON" "$ICON_NAME" || true
          ICON_SET=1
        fi
      fi
    fi
    rm -f "${TMP_ICON:-}" || true
  fi

  # ----- Launcher script (so dmenu/rofi PATH finds it) -----
  info "Creating launcher: $APP_BIN"
  cat >"$APP_BIN" <<'LAUNCH'
#!/usr/bin/env bash
set -euo pipefail
BROWSER_BIN="__BROWSER__"
APP_URL="__APP_URL__"
APP_ID="__APP_ID__"
PROFILE_DIR="$HOME/.local/share/webapps/${APP_ID}"
CLASS="WebApp-__APP_ID__"

ARGS=( --class="$CLASS" --app="$APP_URL" )
if [[ -d "$PROFILE_DIR" ]]; then
  ARGS+=( --user-data-dir="$PROFILE_DIR" --profile-directory=Default )
fi

if [[ -n "$BROWSER_BIN" ]]; then
  exec "$BROWSER_BIN" "${ARGS[@]}" >/dev/null 2>&1 &
else
  echo "No supported browser found in PATH. Install brave/chromium/google-chrome-stable and try again." >&2
  exit 127
fi
LAUNCH

  # Replace placeholders
  local ESC_URL; ESC_URL="$(printf '%s' "$APP_URL" | sed -e 's/[\/&]/\\&/g')"
  sed -i "s|__BROWSER__|$BROWSER_BIN|g" "$APP_BIN"
  sed -i "s|__APP_URL__|$ESC_URL|g" "$APP_BIN"
  sed -i "s|__APP_ID__|$APP_SAFE_ID|g" "$APP_BIN"
  chmod +x "$APP_BIN"

  # Drop separate profile dir if user said "n"
  if [[ "${sep,,}" != "y" ]]; then
    rmdir "$PROFILE_DIR" 2>/dev/null || true
  fi

  # ----- .desktop file (so rofi/drun shows it nicely) -----
  local DESKTOP_FILE="$APP_APPS_DIR/${APP_SAFE_ID}.desktop"
  info "Creating desktop entry: $DESKTOP_FILE"
  {
    echo "[Desktop Entry]"
    echo "Name=${APP_NAME}"
    echo "Comment=WebApp for ${APP_URL}"
    echo "Exec=${APP_BIN}"
    echo "Terminal=false"
    echo "Type=Application"
    if [[ $ICON_SET -eq 1 ]]; then
      echo "Icon=${ICON_NAME}"
    fi
    echo "Categories=Network;"
    echo "StartupWMClass=WebApp-${APP_SAFE_ID}"
  } >"$DESKTOP_FILE"

  ok "Created '${APP_NAME}' → ${APP_BIN} + ${DESKTOP_FILE}"
}

# ---------- Interactive (manual) flow ----------
manual_create_flow() {
  say "${BOLD}Create a new WebApp shortcut${RESET}"
  read -rp "  1) App name (e.g., Instagram): " APP_NAME
  APP_NAME="${APP_NAME:-WebApp}"

  read -rp "  2) App URL (e.g., https://instagram.com): " APP_URL
  if [[ -z "$APP_URL" ]]; then
    err "App URL cannot be empty."
    return 1
  fi

  read -rp "  3) Icon URL (PNG or SVG) — press Enter to skip: " ICON_URL
  local sep
  while true; do
    read -rp "  4) Use a separate browser profile for this app? (y/n): " sep
    sep="${sep,,}"
    [[ "$sep" == "y" || "$sep" == "n" ]] && break
    warn "Please answer with 'y' or 'n'."
  done

  create_webapp_core "$APP_NAME" "$APP_URL" "$sep" "$ICON_URL"
}

# ---------- Preset categories ----------
# Keep these lists super easy to extend: just append lines "Name|URL".
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
  "DeepSeek (AI)|https://search.deepseek.com/"
)

batch_create_category() {
  local category_name="$1"; shift
  local -n items="$1"   # nameref to the array passed in
  info "Creating '${category_name}' webapp shortcuts…"
  # For batch creation we default to using the NORMAL browser profile (sep='n')
  # so links open as your already-logged-in self. Change to 'y' if you prefer isolation.
  local sep="n"
  local count=0
  for entry in "${items[@]}"; do
    local name="${entry%%|*}"
    local url="${entry#*|}"
    create_webapp_core "$name" "$url" "$sep" ""
    ((count++)) || true
  done
  ok "Created $count '${category_name}' shortcuts."
}

# ---------- Main menu ----------
main_menu() {
  say ""
  say "${BOLD}Linux WebApp Builder${RESET}"
  say "Choose one of the following options:"
  say "  1) Create a single (manual) webapp"
  say "  2) Create all 'Work' webapps"
  say "  3) Create all 'Private' webapps"
  say "  4) Exit"
  say ""

  local choice
  read -rp "Your choice [1-4]: " choice
  case "${choice:-}" in
    1) manual_create_flow ;;
    2) batch_create_category "Work" CATEGORY_WORK ;;
    3) batch_create_category "Private" CATEGORY_PRIVATE ;;
    4) exit 0 ;;
    *) warn "Invalid choice." ;;
  esac
}

# ---------- Entry point ----------
main() {
  require_arch
  ensure_requirements

  # Loop until user exits
  while true; do
    main_menu
    say ""
    local again
    while true; do
      read -rp "Do you want to do another action? (y/n): " again
      again="${again,,}"
      [[ "$again" == "y" || "$again" == "n" ]] && break
      warn "Please answer with 'y' or 'n'."
    done
    [[ "$again" == "y" ]] || break
  done

  ok "All done. Enjoy your WebApps!"
}

main "$@"
