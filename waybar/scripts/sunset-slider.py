#!/usr/bin/env python3
"""Themed night-light intensity popup for the waybar `custom/sunset` module.

Pops a small, layer-shell window anchored below the bar on the right edge of
the active monitor.  Kanagawa-themed to match the `#custom-sunset` waybar CSS.
The user drags a slider to set filter strength (0-100); the value is persisted
and the shader is re-applied live (only while the night-light is already on).
The popup auto-dismisses after 1.5s of pointer/idle inactivity and fades
in/out.

State files come from sunset.sh's cache dir, so the two stay in sync:
    $XDG_CACHE_HOME/waybar-sunset/{intensity,night-light.glsl}
"""

from __future__ import annotations

import atexit
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gdk, Gtk, GtkLayerShell  # noqa: E402

# ---------------------------------------------------------------------------
# Config — mirrors ~/dotfiles/waybar/themes/kanagawa.css + #custom-sunset style
# ---------------------------------------------------------------------------
SHADER_SRC = "/usr/share/hyprshade/shaders/blue-light-filter.glsl"
STRENGTH_LINE = "const float temperatureStrength = 1.0;"
EMPTY = "[[EMPTY]]"
DEFAULT_INTENSITY = 50
IDLE_MS = 1000          # auto-dismiss after 1s of no interaction
FADE_STEPS = 8         # opacity animation ticks (in + out)
FADE_TICK_MS = 16      # ~60fps
POPUP_W = 250          # approx total popup width (scale 220 + box padding), used for centering

# Kanagawa palette (kept in sync with themes/kanagawa.css)
C_BG = "#1f1f28"        # base         — popup background / slider trough empty
C_BG2 = "#2a2a37"       # surface0
C_FG = "#dcd7ba"        # text         — label
C_SUB = "#c8c093"       # subtext1
C_ACCENT = "#ffa066"    # peach        — slider fill, accent (matches #custom-sunset.on)
C_BORDER = "#565575"   # overlay0     — popup border

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "waybar-sunset"
INTENSITY_FILE = CACHE_DIR / "intensity"
GEN_SHADER = CACHE_DIR / "night-light.glsl"
LOCK_FILE = CACHE_DIR / "slider.lock"   # PID guard shared with sunset.sh

# ---------------------------------------------------------------------------
# State helpers (shared format with sunset.sh)
# ---------------------------------------------------------------------------


def clamp(v: int) -> int:
    return max(0, min(100, v))


def read_intensity() -> int:
    try:
        return clamp(int(INTENSITY_FILE.read_text().strip()))
    except (FileNotFoundError, ValueError):
        return DEFAULT_INTENSITY


def write_intensity(v: int) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    INTENSITY_FILE.write_text(str(clamp(v)))


def _lua_escape_str(s: str) -> str:
    return s.translate(str.maketrans({"\\": r"\\\\", "'": r"\'"}))


def set_shader(path: str) -> None:
    """Apply/clear decoration:screen_shader via the `eval` dispatcher.

    Hyprland 0.56 rejects `hyprctl keyword` for this option ("keyword can't
    work with non-legacy parsers. Use eval."); the `hl.config({ ... })` call
    form (the same hyprshade 5.0.0 uses) is required.
    """
    subprocess.run(
        ["hyprctl", "eval", f"hl.config({{ decoration = {{ screen_shader = '{_lua_escape_str(path)}' }} }})"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def current_shader() -> str | None:
    try:
        out = subprocess.check_output(
            ["hyprctl", "-j", "getoption", "decoration:screen_shader"],
            text=True, stderr=subprocess.DEVNULL,
        )
        s = json.loads(out).get("str", "").strip()
        return None if s == EMPTY or not s else s
    except Exception:
        return None


def is_on() -> bool:
    return current_shader() is not None


def apply_live() -> None:
    """Re-bake the generated shader at the current intensity and (re)apply it
    only if the night-light is currently on."""
    if not is_on():
        return
    strength = f"{read_intensity() / 100:.2f}"
    if not Path(SHADER_SRC).exists():
        return
    body = Path(SHADER_SRC).read_text()
    body = body.replace(STRENGTH_LINE, f"const float temperatureStrength = {strength};")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    GEN_SHADER.write_text(body)
    set_shader(str(GEN_SHADER))


# ---------------------------------------------------------------------------
# Popup
# ---------------------------------------------------------------------------


class Cursor:
    """Pointer coords captured at right-click time (global Hyprland space)."""
    def __init__(self, x: int = 0, y: int = 0) -> None:
        self.x = x
        self.y = y

class SunsetPopup(Gtk.Window):
    def __init__(self, ctx: Cursor | None = None) -> None:
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.ctx = ctx or Cursor()
        self.set_title("Night light intensity")
        self.set_decorated(False)
        self.set_resizable(False)
        # Enable per-pixel alpha so the rgba() background from CSS actually
        # blends with whatever sits behind the layer-shell surface.
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)

        # Drag handling so only left-drag moves the **slider knob**, not the
        # window (we don't make it draggable anyway; this is about input focus).
        self.add_events(
            Gdk.EventMask.POINTER_MOTION_MASK
            | Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.SCROLL_MASK
            | Gdk.EventMask.ENTER_NOTIFY_MASK
            | Gdk.EventMask.LEAVE_NOTIFY_MASK
        )

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        # Position the popup directly under the icon: anchor to the top-left
        # corner of the active monitor, then offset by the cursor coords
        # captured at click time. The moon sits where the cursor was, so the
        # popup drops straight down from it, horizontally centered on the icon.
        cx, cy = ctx.x, ctx.y
        # Pin the surface to the monitor the cursor is on so layer-shell margins
        # are interpreted relative to that monitor, not the primary one. Use
        # Gdk's own monitor lookup; its Wayland logical geometry mirrors the
        # global compositor layout under wlroots/Hyprland.
        mon = self._monitor_at(cx, cy)
        if mon is not None:
            GtkLayerShell.set_monitor(self, mon)
            mx, my = mon._hypr_x, mon._hypr_y
            mw = mon._hypr_w
        else:
            mx = my = 0
            mw = 2 ** 31  # skip clamping if we don't know

        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, False)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, False)

        local_x = cx - mx              # pointer within this monitor
        # Center the popup (~POPUP_W wide) under the cursor, clamp to the monitor.
        margin_left = int(local_x - POPUP_W / 2)
        margin_left = max(4, min(margin_left, mw - POPUP_W - 4))
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, margin_left)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, int(cy - my + 6))
        # Don't grab keyboard — keep the bar's interactions intact.
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)

        self._apply_css()
        self._build_ui()

        self._idle_id = 0
        self._fade_id = 0
        self._closing = False

        # Start invisible; fade in once realised.
        self.set_opacity(0.0)
        self.connect("realize", self._on_realize)
        self.connect("draw", self._on_draw)
        self.connect("motion-notify-event", self._poke)
        self.connect("button-press-event", self._poke)
        self.connect("button-release-event", self._poke)
        self.connect("scroll-event", self._poke)
        self.connect("enter-notify-event", self._poke)
        self.connect("leave-notify-event", self._poke)

    # ----- Monitor lookup ------------------------------------------------
    @staticmethod
    def _monitor_at(x: int, y: int):
        """Return a Gdk.Monitor whose geometry contains the global cursor point.
        On Wayland under wlroots compositors (Hyprland), Gdk's monitor layout
        matches the compositor's global coordinate space, so the same x/y used
        by `hyprctl cursorpos` can be fed to `get_monitor_at_point`. We stash
        the compositor geometry on the returned object for margin math."""
        try:
            display = Gdk.Display.get_default()
            mon = display.get_monitor_at_point(x, y)
        except Exception:
            return None
        if mon is None:
            # Fall back to primary monitor.
            try:
                mon = Gdk.Display.get_default().get_primary_monitor()
            except Exception:
                return None
            if mon is None:
                return None
        # Use Gdk's logical geometry for the compositor layout. If it looks off
        # (e.g. transformed output), fall back to hyprctl's reported geometry.
        rect = mon.get_geometry()
        mon._hypr_x = rect.x
        mon._hypr_y = rect.y
        mon._hypr_w = rect.width
        # Hyprland rotates some outputs (e.g. DVI-I-2 vertical). When Gygeometry.width is the post-rotation value but the compositor's global x/y
        # layout uses pre-rotation bounds. Cross-check with hyprctl monitors.
        try:
            mons = json.loads(
                subprocess.check_output(["hyprctl", "monitors", "-j"],
                                        text=True, stderr=subprocess.DEVNULL)
            )
            for m in mons:
                if (m["x"] <= x < m["x"] + m["width"]
                        and m["y"] <= y < m["y"] + m["height"]):
                    mon._hypr_x = m["x"]
                    mon._hypr_y = m["y"]
                    # Use the larger of width/height for clamping so the popup
                    # stays on-screen even for rotated outputs.
                    mon._hypr_w = max(m["width"], m["height"])
                    break
        except Exception:
            pass
        return mon

    # ----- UI -------------------------------------------------------------
    def _apply_css(self) -> None:
        css = f"""
        window {{
            background-color: rgba(31, 31, 40, 0.5);
            border: 1px solid {C_BORDER};
            border-radius: 10px;
            box-shadow: 0 6px 18px rgba(0,0,0,0.45);
        }}
        .label {{
            color: {C_FG};
            font-family: 'JetBrains Mono', 'Symbols Nerd Font', monospace;
            font-size: 12px;
            font-weight: 600;
        }}
        scale trough {{
            background-color: {C_BG2};
            border-radius: 6px;
            min-height: 8px;
        }}
        scale highlight {{
            background-color: {C_ACCENT};
            border-radius: 6px;
        }}
        scale slider {{
            background-color: {C_ACCENT};
            border: 2px solid {C_BG};
            border-radius: 50%;
            min-width: 14px;
            min-height: 14px;
            box-shadow: 0 2px 6px rgba(0,0,0,0.5);
        }}
        scale slider:hover {{
            background-color: {C_FG};
        }}
        .value {{
            color: {C_ACCENT};
        }}
        """
        prov = Gtk.CssProvider()
        prov.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            prov,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1,
        )

    def _build_ui(self) -> None:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        outer.set_margin_top(10)
        outer.set_margin_bottom(10)
        outer.set_margin_start(14)
        outer.set_margin_end(14)

        # Header: icon + label + live value
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        icon = Gtk.Label(label="󰖔")
        icon.get_style_context().add_class("label")
        icon.set_opacity(0.95)
        self.value_lbl = Gtk.Label(label=f"{read_intensity()}%")
        self.value_lbl.get_style_context().add_class("label")
        self.value_lbl.get_style_context().add_class("value")
        self.value_lbl.set_xalign(1.0)

        title = Gtk.Label(label="Night light")
        title.get_style_context().add_class("label")
        title.set_xalign(0.0)

        header.pack_start(icon, False, False, 0)
        header.pack_start(title, True, True, 0)
        header.pack_end(self.value_lbl, False, False, 0)
        outer.pack_start(header, False, False, 0)

        self.scale = Gtk.Scale(
            orientation=Gtk.Orientation.HORIZONTAL,
            adjustment=Gtk.Adjustment.new(read_intensity(), 0, 100, 5, 5, 0),
        )
        self.scale.set_draw_value(False)
        self.scale.set_hexpand(True)
        self.scale.set_size_request(220, -1)
        self.scale.connect("value-changed", self._on_value_changed)
        self.scale.connect("button-press-event", self._poke)
        self.scale.connect("button-release-event", self._poke)
        self.scale.connect("motion-notify-event", self._poke)
        self.scale.connect("scroll-event", self._poke)
        outer.pack_start(self.scale, True, True, 0)

        self.add(outer)

    # ----- Life cycle -----------------------------------------------------
    def _on_realize(self, _w) -> None:
        self._fade(True)

    def _on_draw(self, _w, _cr) -> bool:
        # First paint is done — resume the idle clock now that we're visible.
        self._poke()
        return False

    # ----- Idle / dismiss --------------------------------------------------
    def _poke(self, *args) -> bool:
        """Any user activity resets the idle dismiss timer."""
        if self._closing:
            return False
        self._reschedule_idle()
        return False

    def _reschedule_idle(self) -> None:
        if self._idle_id:
            GLib.source_remove(self._idle_id)
        self._idle_id = GLib.timeout_add(IDLE_MS, self._begin_close)

    def _begin_close(self) -> bool:
        self._fade(False)
        return False

    # ----- Fade animation -------------------------------------------------
    def _fade(self, opening: bool) -> None:
        if self._fade_id:
            GLib.source_remove(self._fade_id)
            self._fade_id = 0

        steps = list(self._fade_steps(opening))

        def tick(i: int = 0) -> bool:
            if i >= len(steps):
                if not opening:
                    self._closing = True
                    Gtk.main_quit()
                self._fade_id = 0
                return False
            self.set_opacity(steps[i])
            self.queue_draw()
            self._fade_id = GLib.timeout_add(FADE_TICK_MS, tick, i + 1)
            return False

        self._fade_id = GLib.timeout_add(FADE_TICK_MS, tick, 0)

    @staticmethod
    def _fade_steps(opening: bool):
        # Eased opacity: 8 steps with a slight ease-in-out curve (0.0 -> 1.0
        # on open, 1.0 -> 0.0 on close).
        n = FADE_STEPS
        for i in range(n + 1):
            p = i / n
            if opening:
                yield p * p * (3 - 2 * p)          # smoothstep up
            else:
                yield 1 - (p * p * (3 - 2 * p))    # smoothstep down

    # ----- Slider ----------------------------------------------------------
    def _on_value_changed(self, _scale) -> None:
        v = int(round(self.scale.get_value()))
        self.value_lbl.set_label(f"{v}%")
        write_intensity(v)
        apply_live()
        self._poke()


def release_lock() -> None:
    """Remove the slider PID lock on exit so the next right-click can spawn
    a fresh popup. Only removes it if it belongs to this process."""
    try:
        if LOCK_FILE.exists():
            pid = LOCK_FILE.read_text().strip()
            if pid == str(os.getpid()):
                LOCK_FILE.unlink()
    except OSError:
        pass


def main() -> int:
    if not shutil.which("hyprctl"):
        print("hyprctl not found", file=sys.stderr)
        return 1
    if not Path(SHADER_SRC).exists():
        print(f"shader not found: {SHADER_SRC}", file=sys.stderr)
        return 1
    # Optional arg: "x, y" from `hyprctl cursorpos`, to anchor the popup
    # beneath the icon where the right-click happened.
    ctx = Cursor()
    if len(sys.argv) > 1:
        s = sys.argv[1].strip()
        if "," in s:
            try:
                xs, ys = s.split(",", 1)
                ctx = Cursor(int(xs.strip()), int(ys.strip()))
            except ValueError:
                pass
    # Make this process the canonical owner of the lock (overwrite anything
    # sunset.sh wrote, in case the PID it captured was slightly off).
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    LOCK_FILE.write_text(str(os.getpid()))
    atexit.register(release_lock)

    win = SunsetPopup(ctx)
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())