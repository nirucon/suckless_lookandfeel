#!/usr/bin/env bash
#
# apply-screenlayout
# ------------------
# Simple hostname-based monitor layout loader for X11/xrandr.
#
# Purpose:
# - Apply a specific monitor layout on selected hosts
# - Keep a safe default for all other machines
# - Make it very easy to add more hosts later
#
# How it works:
# 1. Detect current hostname
# 2. Match hostname in the case block below
# 3. Run the xrandr layout for that host
# 4. If no hostname matches, do nothing (safe default)
#
# Notes:
# - Intended to be called early from X startup, before or during dwm start
# - Requires xrandr and X11
# - If outputs change names on a machine, update that host block only
#
# Add a new host:
# - Copy an existing host block
# - Change the hostname
# - Replace the xrandr command with the layout for that machine
#

set -u

HOSTNAME_NOW="$(hostname)"

# Exit quietly if xrandr is not installed or not available.
command -v xrandr >/dev/null 2>&1 || exit 0

# Exit quietly if DISPLAY is not set.
# This prevents accidental runs outside an X session.
[ -n "${DISPLAY:-}" ] || exit 0

case "$HOSTNAME_NOW" in
  othala)
    # Othala:
    # - Two monitors stacked vertically
    # - Top monitor is upside down
    # - Bottom monitor is normal
    #
    # Based on current outputs:
    #   DisplayPort-5 = top, inverted
    #   DisplayPort-4 = bottom, normal
    xrandr \
      --output DisplayPort-4 --mode 2560x1440 --pos 0x1440 --rotate normal \
      --output DisplayPort-5 --mode 2560x1440 --pos 0x0    --rotate inverted
    ;;

  # Example for future hosts:
  #
  # oden)
  #   xrandr \
  #     --output DP-1 --primary --mode 2560x1440 --pos 0x0 --rotate normal \
  #     --output HDMI-1 --mode 1920x1080 --right-of DP-1 --rotate normal
  #   ;;
  #
  # laptopname)
  #   xrandr --auto
  #   ;;

  *)
    # Default:
    # Do nothing for hosts without a dedicated layout.
    # This keeps the script safe on laptops or single-screen machines.
    :
    ;;
esac

exit 0
