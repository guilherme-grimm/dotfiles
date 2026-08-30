#!/bin/bash

# Waybar night-light toggle with an intensity slider.
#
# Uses Hyprland's `decoration:screen_shader` (a GPU fragment shader applied at
# render time to EVERY output) instead of `wlsunset`. The DisplayLink dock
# exposes external monitors as DVI-I-1/DVI-I-2, whose evdi driver rejects the
# wlr-gamma-control ramps wlsunset relies on — so wlsunset only ever warmed
# the laptop panel (eDP-1). A screen shader runs in Hyprland's renderer before
# the buffer reaches evdi, so it covers all three monitors equally.
#
# Shader: the blue-light-filter.glsl shipped by the `hyprshade` package. We use
# hyprshade's shader but NOT its CLI — we drive `decoration:screen_shader`
# directly via `hyprctl eval hl.config({ ... })`, the same call hyprshade 5.0.0
# makes in its shader/hyprctl.py. An earlier version of this script used the
# `keyword` dispatcher, but Hyprland 0.56 rejects that for screen_shader
# ("keyword can't work with non-legacy parsers. Use eval.") and silently no-ops.
# `getoption` (either `:` or `.` separator) still works for reading state, so we
# keep it for current_shader / is_on.
#
# Intensity (0-100) scales the shader's `temperatureStrength` const (0.0-1.0).
# Hyprland's screen_shader does not reliably forward custom uniforms, so we
# bake the value into a generated copy of the shader and apply that path. The
# value lives in a cache dir (not the dotfiles repo) so the repo stays clean.

SHADER_SRC="/usr/share/hyprshade/shaders/blue-light-filter.glsl"
EMPTY="[[EMPTY]]"
DEFAULT_INTENSITY=50          # 0-100; hyprshade's shader is pinned to 1.0, which is too strong here.
STRENGTH_LINE='const float temperatureStrength = 1.0;'

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-sunset"
INTENSITY_FILE="$CACHE_DIR/intensity"
GEN_SHADER="$CACHE_DIR/night-light.glsl"
LOCK_FILE="$CACHE_DIR/slider.lock"   # guard against spawning multiple popups

ensure_dirs() {
    mkdir -p "$CACHE_DIR"
}

read_intensity() {
    ensure_dirs
    if [ -f "$INTENSITY_FILE" ]; then
        cat "$INTENSITY_FILE" 2>/dev/null \
            | tr -dc '0-9' \
            | awk -v d="$DEFAULT_INTENSITY" '{ v=$1+0; if (v<0||v>100||v=="") print d; else print v }' \
            | head -1
    else
        echo "$DEFAULT_INTENSITY"
    fi
}

write_intensity() {
    ensure_dirs
    local v
    v="$(printf '%s' "$1" | tr -dc '0-9' | awk '{ v=$1+0; if (v<0) v=0; if (v>100) v=100; printf "%d", v }')"
    printf '%s' "$v" > "$INTENSITY_FILE"
}

# Bake the current intensity into a generated copy of the bundled shader and
# print the generated path.
render_shader() {
    ensure_dirs
    local strength intensity
    intensity="$(read_intensity)"
    # integer percent -> 0.xxx float (two-decimal precision)
    strength="$(awk -v i="$intensity" 'BEGIN { printf "%.2f", i/100 }')"
    if [ ! -f "$SHADER_SRC" ]; then
        echo "source shader not found: $SHADER_SRC" >&2
        return 1
    fi
    sed "s|${STRENGTH_LINE}|const float temperatureStrength = ${strength};|" "$SHADER_SRC" > "$GEN_SHADER"
    echo "$GEN_SHADER"
}

# Print the currently-applied shader path (or the EMPTY sentinel).
current_shader() {
    hyprctl -j getoption decoration:screen_shader 2>/dev/null \
        | jq -r '.str // empty' 2>/dev/null
}

# Escape a string for a single-quoted Lua literal (backslash -> \\, ' -> \').
# awk is used because bash parameter-expansion quoting around a single quote
# is fragile here and can swallow the following function definition.
lua_escape_str() {
    printf '%s' "$1" | awk '{ gsub(/\\/, "\\\\"); gsub(/\047/, "\\\047"); printf "%s", $0 }'
}

# Set decoration:screen_shader via the `eval` dispatcher. Hyprland 0.56 rejects
# the `keyword` dispatcher for this option ("keyword can't work with non-legacy
# parsers. Use eval."), so the functional-call form hyprshade 5.0 uses is
# required:  hl.config({ decoration = { screen_shader = '<path>' } })
set_shader() {
    local path
    path="$(lua_escape_str "$1")"
    hyprctl eval "hl.config({ decoration = { screen_shader = '${path}' } })" >/dev/null
}

is_on() {
    local cur
    cur="$(current_shader)"
    [ -n "$cur" ] && [ "$cur" != "$EMPTY" ]
}

apply_on() {
    local gen
    gen="$(render_shader)" || return 1
    set_shader "$gen"
}

apply_off() {
    set_shader "$EMPTY"
}

# Open the themed intensity popup (sunset-slider.py). The popup writes the
# chosen intensity and re-applies the shader live as the user drags. It
# auto-dismisses after ~1.5s of idle and fades out. It is positioned just below
# the moon icon by anchoring on the pointer coords captured at click time
# (the cursor sits on the icon during the right-click).
#
# A PID lock guards against spamming the popup: if a popup is already open,
# the right-click is a no-op. Stale locks (dead PID) self-heal so a crashed
# popup can't wedge the feature.
slider() {
    ensure_dirs
    local script cursor pid

    # Already-open check: a live PID in the lock means a popup is up.
    if [ -f "$LOCK_FILE" ]; then
        pid="$(tr -dc '0-9' < "$LOCK_FILE" 2>/dev/null | head -1)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0                      # popup already open — ignore the click
        fi
        rm -f "$LOCK_FILE"               # stale lock; clean and proceed
    fi

    script="$(cd "$(dirname "$0")" && pwd)/sunset-slider.py"
    if [ ! -f "$script" ]; then
        echo "slider popup not found: $script" >&2
        return 1
    fi
    cursor="$(hyprctl cursorpos 2>/dev/null | tr -d ' ' | head -1)"
    GDK_BACKEND=wayland python3 "$script" "$cursor" >/dev/null 2>&1 &
    printf '%s' "$!" > "$LOCK_FILE"
}

status_json() {
    local intensity label tip
    intensity="$(read_intensity)"
    if is_on; then
        label="󰖔"
        tip="Night light ON · ${intensity}%"
        class="on"
    else
        label="󰖕"
        tip="Night light OFF · ${intensity}%"
        class="off"
    fi
    jq -c -n --arg t "$tip" --arg l "$label" --arg c "$class" \
        '{text: $l, tooltip: $t, class: $c}'
}

case "$1" in
    toggle)
        if is_on; then
            apply_off
        else
            apply_on
        fi
        ;;
    slider)
        slider
        ;;
    set)                           # convenience: `sunset.sh set 70`
        [ -n "$2" ] && write_intensity "$2"
        is_on && apply_on
        ;;
    *)
        status_json
        ;;
esac