#!/bin/bash
# Screenshot med select + optional save med undermappar + rename + browse old screenshots
# Del av DWM config by Nicklas Rudolfsson

# Ta screenshot till temp-fil
tmp=$(mktemp /tmp/shot-XXXXXX.png)
maim -s "$tmp" || exit 1

# Kopiera till urklipp först (detta händer alltid)
xclip -selection clipboard -t image/png -i "$tmp"

# Första valet: Var vill du spara?
choice=$(echo -e "No\nSave to /Screenshots\nSave to /Screenshots/Important\nSave to /Screenshots/Fun\nSave & edit in Gimp\nSave & view in sxiv\nBrowse old (list)\nBrowse old (visual)" |
  rofi -dmenu -i -p "Save screenshot?" \
    -theme-str 'window {width: 400px;} listview {lines: 8;}')

# Funktion för att spara med optional rename
save_with_rename() {
  local target_dir="$1"
  local timestamp=$(date +%F_%H-%M-%S)

  # Fråga om användaren vill byta namn
  rename_choice=$(echo -e "No\nYes" |
    rofi -dmenu -i -p "Rename file before saving?" \
      -theme-str 'window {width: 350px;} listview {lines: 2;}')

  if [[ "$rename_choice" == "Yes" ]]; then
    # Låt användaren skriva ett eget namn
    custom_name=$(rofi -dmenu -p "Enter filename (without .png):" \
      -theme-str 'window {width: 400px;}' </dev/null)

    if [[ -n "$custom_name" ]]; then
      # Ta bort .png om användaren skrev det
      custom_name="${custom_name%.png}"
      file="$target_dir/${custom_name}_${timestamp}.png"
    else
      # Om användaren inte skrev något, använd bara timestamp
      file="$target_dir/${timestamp}.png"
    fi
  else
    # Standard: bara timestamp
    file="$target_dir/${timestamp}.png"
  fi

  mkdir -p "$target_dir"
  mv "$tmp" "$file"
  echo "$file"
}

# Funktion för att browse gamla screenshots med rofi (textlista)
browse_old_screenshots_rofi() {
  local screenshots_dir="$HOME/Pictures/Screenshots"

  # Kolla om mappen finns (följ symlink med cd)
  if [[ ! -e "$screenshots_dir" ]]; then
    notify-send 'Screenshot Browser' 'Screenshots folder not found'
    rm -f "$tmp"
    exit 0
  fi

  # Hitta alla bilder, sortera efter datum (nyast först)
  # Använd -L för att följa symlinks
  mapfile -t images < <(find -L "$screenshots_dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -printf "%T@ %p\n" 2>/dev/null | sort -rn | cut -d' ' -f2-)

  if [[ ${#images[@]} -eq 0 ]]; then
    notify-send 'Screenshot Browser' 'No screenshots found'
    rm -f "$tmp"
    exit 0
  fi

  # Skapa lista med relativa sökvägar för bättre läsbarhet
  declare -a display_list
  for img in "${images[@]}"; do
    rel_path="${img#$screenshots_dir/}"
    display_list+=("$rel_path")
  done

  # Visa i rofi
  selected_index=-1
  for i in "${!display_list[@]}"; do
    if selected=$(printf '%s\n' "${display_list[@]}" | rofi -dmenu -i -p "Select screenshot (text search):" -format 'i' -theme-str 'window {width: 600px;} listview {lines: 15;}'); then
      selected_index=$selected
      break
    else
      # Användaren tryckte Escape
      rm -f "$tmp"
      exit 0
    fi
  done

  # Om något valdes
  if [[ $selected_index -ge 0 ]]; then
    selected_file="${images[$selected_index]}"
    xclip -selection clipboard -t image/png -i "$selected_file"
    notify-send 'Screenshot Browser' "Copied to clipboard: $(basename "$selected_file")"
  fi

  # Ta bort den nya screenshoten vi tog (eftersom vi browsade istället)
  rm -f "$tmp"
}

# Funktion för att browse gamla screenshots med sxiv (visuell thumbnails)
browse_old_screenshots_sxiv() {
  local screenshots_dir="$HOME/Pictures/Screenshots"

  # Kolla om mappen finns (följ symlink)
  if [[ ! -e "$screenshots_dir" ]]; then
    notify-send 'Screenshot Browser' 'Screenshots folder not found'
    rm -f "$tmp"
    exit 0
  fi

  # Kolla om det finns bilder (följ symlinks med -L)
  if [[ -z $(find -L "$screenshots_dir" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null) ]]; then
    notify-send 'Screenshot Browser' 'No screenshots found'
    rm -f "$tmp"
    exit 0
  fi

  # Öppna sxiv för att browsea (rekursivt, inkluderar undermappar)
  # -r = rekursiv, -t = thumbnail mode, -o = output selected file
  notify-send 'Screenshot Browser' 'Use arrows to navigate, Enter to copy, q to quit'

  selected=$(sxiv -t -o -r "$screenshots_dir" 2>/dev/null)

  if [[ -n "$selected" ]]; then
    # Kopiera den valda bilden till clipboard
    xclip -selection clipboard -t image/png -i "$selected"
    notify-send 'Screenshot Browser' "Copied to clipboard: $(basename "$selected")"
  fi

  # Ta bort den nya screenshoten vi tog (eftersom vi browsade istället)
  rm -f "$tmp"
}

case "$choice" in
"No")
  # Ta bort temp-filen
  rm -f "$tmp"
  notify-send 'Screenshot' 'Copied to clipboard (not saved)'
  ;;

"Save to /Screenshots")
  dir="$HOME/Pictures/Screenshots"
  file=$(save_with_rename "$dir")
  notify-send 'Screenshot' "Saved to Screenshots: $(basename "$file")"
  ;;

"Save to /Screenshots/Important")
  dir="$HOME/Pictures/Screenshots/Important"
  file=$(save_with_rename "$dir")
  notify-send 'Screenshot' "Saved to Important: $(basename "$file")"
  ;;

"Save to /Screenshots/Fun")
  dir="$HOME/Pictures/Screenshots/Fun"
  file=$(save_with_rename "$dir")
  notify-send 'Screenshot' "Saved to Fun: $(basename "$file")"
  ;;

"Save & edit in Gimp")
  dir="$HOME/Pictures/Screenshots"
  mkdir -p "$dir"
  file="$dir/$(date +%F_%H-%M-%S).png"
  mv "$tmp" "$file"
  notify-send 'Screenshot' "Saved & opening in Gimp: $(basename "$file")"
  gimp "$file" &
  ;;

"Save & view in sxiv")
  dir="$HOME/Pictures/Screenshots"
  mkdir -p "$dir"
  file="$dir/$(date +%F_%H-%M-%S).png"
  mv "$tmp" "$file"
  notify-send 'Screenshot' "Saved & opening in sxiv: $(basename "$file")"
  sxiv "$file" &
  ;;

"Browse old (list)")
  browse_old_screenshots_rofi
  ;;

"Browse old (visual)")
  browse_old_screenshots_sxiv
  ;;

*)
  # Om användaren stänger dialogen eller trycker Escape
  rm -f "$tmp"
  ;;
esac
