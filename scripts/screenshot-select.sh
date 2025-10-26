#!/bin/bash
# Screenshot med select + optional save med undermappar + öppna i Gimp/sxiv
# Del av DWM config by Nicklas Rudolfsson

# Ta screenshot till temp-fil
tmp=$(mktemp /tmp/shot-XXXXXX.png)
maim -s "$tmp" || exit 1

# Kopiera till urklipp först (detta händer alltid)
xclip -selection clipboard -t image/png -i "$tmp"

# Fråga om användaren vill spara och var
# Använder rofi för snygg prompt som matchar din MatteBlack-tema
choice=$(echo -e "Save to /Screenshots\nSave to /Screenshots/Important\nSave to /Screenshots/Fun\nSave & edit in Gimp\nSave & view in sxiv\nNo" |
  rofi -dmenu -i -p "Save screenshot?" \
    -theme-str 'window {width: 400px;} listview {lines: 6;}')

case "$choice" in
"Save to /Screenshots")
  dir="$HOME/Pictures/Screenshots"
  mkdir -p "$dir"
  file="$dir/$(date +%F_%H-%M-%S).png"
  mv "$tmp" "$file"
  notify-send 'Screenshot' "Saved to Screenshots: $(basename "$file")"
  ;;

"Save to /Screenshots/Important")
  dir="$HOME/Pictures/Screenshots/Important"
  mkdir -p "$dir"
  file="$dir/$(date +%F_%H-%M-%S).png"
  mv "$tmp" "$file"
  notify-send 'Screenshot' "Saved to Important: $(basename "$file")"
  ;;

"Save to /Screenshots/Fun")
  dir="$HOME/Pictures/Screenshots/Fun"
  mkdir -p "$dir"
  file="$dir/$(date +%F_%H-%M-%S).png"
  mv "$tmp" "$file"
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

"No" | *)
  # Ta bort temp-filen
  rm -f "$tmp"
  notify-send 'Screenshot' 'Copied to clipboard (not saved)'
  ;;
esac
