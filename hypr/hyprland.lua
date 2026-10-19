-- #######################################################################################
-- HYPRLAND LUA CONFIG  (Hyprland >= 0.55, "Lua-ification" migration, see hypr.land/news/26_lua/)
-- #######################################################################################
--
-- This is a 1:1 port of hyprland.conf. Behavior on versions that support lua:
--   - if a hyprland.lua exists in the config dir, it is loaded INSTEAD of hyprland.conf
--   - the check runs once at startup; restart Hyprland to switch back
--
-- Until you are on 0.55+, the compositor simply ignores this file and keeps loading
-- hyprland.conf, so it acts as a forward-compatible, opt-in fallback.
--
-- You can (and should) split this into multiple files and `require()` them, e.g.:
--   require("monitors")
--   require("binds")
--   require("rules")
-- For now everything is inlined to mirror the original .conf for easy diffing.
-- #######################################################################################

----------------------------------------------------------------------------------
-- MONITORS
----------------------------------------------------------------------------------
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

-- --- HOME (DisplayLink dock) ---
-- Keyed by monitor EDID description, not port name, so swapping
-- cables/docks between computers no longer flips the two externals.
-- HP 524pf 24" - left, vertical (rotated 90°)
hl.monitor({
	output = "desc:HP Inc. HP 524pf VNG5420L4G",
	mode = "1920x1080@100",
	position = "0x0",
	scale = 1,
	transform = 1, -- 1 = 90° rotation (replaces old comma-separated `transform, 1`)
})
-- Gigabyte GS27QA 27" 2K - center, 144Hz
hl.monitor({
	output = "desc:GIGA-BYTE TECHNOLOGY CO. LTD. GS27QA 0x000008D4",
	mode = "2560x1440@143.97",
	position = "1080x0",
	scale = 1,
})
-- Laptop 15" - right
hl.monitor({
	output = "eDP-1",
	mode = "1920x1080@120",
	position = "3640x0",
	scale = 1,
})

-- --- TRAVEL ---
-- hl.monitor({ output = "eDP-1",    mode = "1920x1080@120",   position = "0x0",    scale = 1 })
-- hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@143.97", position = "1920x0", scale = 1 })

----------------------------------------------------------------------------------
-- MY PROGRAMS
----------------------------------------------------------------------------------
-- See https://wiki.hypr.land/Configuring/Keywords/

local terminal = "ghostty"
local fileManager = "dolphin"
local menu = "rofi -show drun"

----------------------------------------------------------------------------------
-- AUTOSTART
----------------------------------------------------------------------------------
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
-- `exec-once = X` → hl.exec_cmd(X) inside the hyprland.start event.
hl.on("hyprland.start", function()
	hl.exec_cmd(terminal)
	hl.exec_cmd("nm-applet")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("waybar & hyprpaper & helium-browser & discord & btop")
	hl.exec_cmd("blueman-applet")
	hl.exec_cmd("systemctl --user start hyprpolkitagent")

	-- GTK dark mode (was `exec = gsettings ...`, runs on every reload in old conf;
	-- start event is sufficient and cheaper)
	hl.exec_cmd('gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"')
	hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')
end)

-- Qt dark mode (env, set before any Qt app starts)
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

----------------------------------------------------------------------------------
-- ENVIRONMENT VARIABLES
----------------------------------------------------------------------------------
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- env = AQ_DRM_DEVICES,/dev/dri/by-path/pci-0000:01:00.0-card:/dev/dri/by-path/pci-0000:00:02.0-card
-- env = GBM_BACKEND,nvidia-drm
-- env = __GLX_VENDOR_LIBRARY_NAME,nvidia
-- env = LIBVA_DRIVER_NAME,nvidia
-- env = NVD_BACKEND,direct
hl.env("AQ_FORCE_LINEAR_BLIT", "0")

----------------------------------------------------------------------------------
-- PERMISSIONS
----------------------------------------------------------------------------------
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- (Left commented in the original conf; ported verbatim.)
--
-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })
-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")

----------------------------------------------------------------------------------
-- LOOK AND FEEL
----------------------------------------------------------------------------------
-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/

-- https://wiki.hypr.land/Configuring/Variables/#general
hl.config({
	general = {
		gaps_in = 2,
		gaps_out = 5,

		border_size = 1,

		-- https://wiki.hypr.land/Configuring/Variables/#variable-types for info about colors
		col = {
			-- old: rgba(33ccffee) rgba(00ff99ee) 00deg
			active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 0 },
			inactive_border = "rgba(595959aa)",
		},

		-- Set to true enable resizing windows by clicking and dragging on borders and gaps
		resize_on_border = false,

		-- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
		allow_tearing = false,

		layout = "dwindle",
	},
})

-- https://wiki.hypr.land/Configuring/Variables/#decoration
hl.config({
	decoration = {
		rounding = 10,
		rounding_power = 2,

		-- Change transparency of focused and unfocused windows
		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = false,
			range = 4,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},

		-- https://wiki.hypr.land/Configuring/Variables/#blur
		blur = {
			enabled = false,
			size = 8,
			passes = 1,
			new_optimizations = true,
			xray = true,
			ignore_opacity = true,
			vibrancy = 0.1696,
		},
	},
})

-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.config({
	animations = {
		enabled = true,
	},
})

-- Default curves, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/#curves
--        NAME,           X0,   Y0,   X1,   Y1
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

-- Default animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
--            NAME,          ONOFF, SPEED, CURVE,        [STYLE]
hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = false, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only" -- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0, rounding = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0, rounding = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
	dwindle = {
		-- pseudotile = true, -- Master switch for pseudotiling. Enabling is bound to mainMod + P below
		preserve_split = true, -- You probably want this
	},
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
	master = {
		new_status = "master",
	},
})

-- https://wiki.hypr.land/Configuring/Variables/#misc
hl.config({
	misc = {
		force_default_wallpaper = -1, -- Set to 0 or 1 to disable the anime mascot wallpapers
		disable_hyprland_logo = false, -- If true disables the random hyprland logo / anime girl background. :(
		vrr = 0,
	},
})

hl.config({
	cursor = {
		no_hardware_cursors = false,
	},
})

----------------------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------------------
-- hl.config({
--   debug = {
--     overlay = true,
--     damage_tracking = 2,
--   },
-- })

----------------------------------------------------------------------------------
-- INPUT
----------------------------------------------------------------------------------
-- https://wiki.hypr.land/Configuring/Variables/#input
hl.config({
	input = {
		kb_layout = "us,br",
		kb_variant = "altgr-intl,abnt2",
		-- kb_model =
		-- kb_options =
		-- kb_rules =

		follow_mouse = 1,

		sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

		touchpad = {
			natural_scroll = false,
		},
	},
})

hl.bind("SUPER + space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})

----------------------------------------------------------------------------------
-- KEYBINDINGS
----------------------------------------------------------------------------------
-- See https://wiki.hypr.land/Configuring/Basics/Binds/

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(
	mainMod .. " + M",
	hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'")
)
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle
hl.bind(mainMod .. " + G", hl.dsp.layout("togglesplit")) -- dwindle only
hl.bind(mainMod .. " + CTRL + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))
-- browser and easy to use ones
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("zen-browser"))
-- Fullscreen and similars
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" })) -- old `fullscreen, 1`
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" })) -- old `fullscreen, 0`
-- Screenshot
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("grimblast copy area && sleep 0.5"))

-- Move focus with mainMod + vim-style H/J/K/L (H=left, J=down, K=up, L=right)
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))

-- Switch workspaces with mainMod + SHIFT + H/L (prev/next)
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.focus({ workspace = "e+1" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + U", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + U", hl.dsp.window.move({ workspace = "special:magic" }))

-- Recover a window that vanished after moving onto the rotated (transform) monitor
-- (Hyprland #8605/#10030: floating windows land off-screen across transform/scale changes)
-- centerwindow only acts on *floating* windows, so the script floats-first when tiled.
-- bind = $mainMod SHIFT, C, centerwindow,   (old commented bind)
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("~/.config/hypr/scripts/recover-window.sh"))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging  (old `bindm`)
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
-- old bindel (e + l flags) → { locked = true, repeating = true }
-- old bindl  (l flag)       → { locked = true }
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
	{ locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

----------------------------------------------------------------------------------
-- WINDOWS AND WORKSPACES
----------------------------------------------------------------------------------
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more
-- See https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/ for workspace rules
-- Rules are evaluated top to bottom, so the order they're written in does matter.

-- Ignore maximize requests from all apps. You'll probably like this.
hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move = "20 monitor_h-120",
	float = true,
})

-- hl.window_rule({
--     name  = "kitty",
--     match = { class = "kitty" },
--     opacity = "1.00 0.9",
-- })

