#!/bin/sh
# Recover a window that vanished after moving onto the rotated (transform) monitor.
# Hyprland #8605 / #10030: floating windows can land off-screen across transform/scale
# changes. `centerwindow` only acts on *floating* windows, so when the vanished window
# is tiled, float it first then center it.
#
# Bind: SUPER + SHIFT + C (see hyprland.conf)
# Side effect: a tiled vanished window ends up floating after recovery (staying visible
# is the priority; toggle it back to tiled manually if you care).

STATE=$(hyprctl -j activewindow 2>/dev/null | jq -r '.floating // empty' 2>/dev/null)

if [ "$STATE" = "true" ]; then
  hyprctl dispatch centerwindow >/dev/null 2>&1
else
  # Tiled (or unknown) — float it so centerwindow can grab it.
  hyprctl dispatch togglefloating >/dev/null 2>&1
  hyprctl dispatch centerwindow >/dev/null 2>&1
fi