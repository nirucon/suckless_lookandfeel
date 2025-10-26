#!/bin/bash
# Screenshot med select + optional save med undermappar + rename + öppna i Gimp/sxiv
# Del av DWM config by Nicklas Rudolfsson

# Ta screenshot till temp-fil
tmp=$(mktemp /tmp/shot-XXXXXX.png)
maim -s "$tmp" || exit 1

# Kopiera till urklipp först (detta händer alltid)
xclip -selection clipboard -t image/png -i "$tmp"

# Första valet: Var vill du spara?
choice=$(echo -e "No\nSave to /Screenshots\nSave to /Screenshots/Important\nSave to /Screenshots/Fun\nSave & edit in Gimp\nSave & view in sxiv" |
  rofi -dmenu -i -p "Save screenshot?" \
    -theme-str 'window {width: 400px;} listview {lines: 6;}')

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

*)
  # Om användaren stänger dialogen eller trycker Escape
  rm -f "$tmp"
  ;;
esac
