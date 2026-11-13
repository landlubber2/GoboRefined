-----------------------------------------------------------------------
--  "gobo11" awesome theme — a clean, modern look for the GoboLinux spin.
--  Everything visual is drawn here with cairo (wallpaper, title bar
--  buttons, launcher icons), so the theme needs almost no image files.
--
--  Dark or light is read from the file "mode" next to rc.lua (the power
--  menu's Light mode / Dark mode button writes it). Default: dark.
-----------------------------------------------------------------------

local gears = require("gears")

local MODE = "dark"
do
   local f = io.open(gears.filesystem.get_configuration_dir() .. "mode", "r")
   if f then
      local word = (f:read("*l") or ""):match("%a+")
      f:close()
      if word == "light" or word == "dark" then MODE = word end
   end
end
local cairo = require("lgi").cairo
local naughty = require("naughty")

local dir = gears.filesystem.get_configuration_dir() .. "themes/gobo11/"
local theme = {}

local palettes = {
   dark = {
      bar       = "#1c1c1cf2",   surface  = "#202020",   surface2 = "#2b2b2b",
      fg        = "#ffffff",     fg_dim   = "#a0a0a0",   border   = "#3d3d3d",
      hover     = "#ffffff1a",   active   = "#ffffff26", accent   = "#4cc2ff",
      menu      = "#2c2c2cf5",
      wall_from = "#070b1a",     wall_to  = "#0d2147",   glow = "#2f6bff",
      waves     = { "#123a8a", "#1a55c4", "#2f7bf0", "#5a5fe8", "#8a54e6", "#3fa9f5" },
   },
   light = {
      bar       = "#f3f3f3f2",   surface  = "#f3f3f3",   surface2 = "#fafafa",
      fg        = "#1b1b1b",     fg_dim   = "#5f5f5f",   border   = "#c9c9c9",
      hover     = "#0000000f",   active   = "#0000001c", accent   = "#005fb8",
      menu      = "#f9f9f9f5",
      wall_from = "#cfe4ff",     wall_to  = "#eaf3ff",   glow = "#ffffff",
      waves     = { "#9cc8ff", "#6fb0ff", "#3f8ef5", "#6f7df0", "#a58af0", "#58b8ff" },
   },
}
local p = palettes[MODE] or palettes.dark
theme.mode = MODE
theme.palette = p

-- Drawing helpers ------------------------------------------------------

local function surface(w, h, draw)
   local img = cairo.ImageSurface("ARGB32", w, h)
   local cr = cairo.Context(img)
   draw(cr, w, h)
   return img
end

local function set_color(cr, hex, alpha)
   local r, g, b, a = gears.color.parse_color(hex)
   cr:set_source_rgba(r, g, b, alpha or a)
end

local function rounded(radius)
   return function(cr, w, h) gears.shape.rounded_rect(cr, w, h, radius) end
end

-- Fonts and base colours -----------------------------------------------

theme.font       = "DejaVu Sans 10"
theme.font_small = "DejaVu Sans 8"
theme.font_title = "DejaVu Sans 9"

theme.fg_normal  = p.fg
theme.fg_focus   = p.fg
theme.fg_urgent  = p.fg
theme.bg_normal  = p.surface
theme.bg_focus   = p.surface2
theme.bg_urgent  = "#c42b1c"
theme.bg_systray = p.surface
theme.systray_icon_spacing = 6

-- Windows ---------------------------------------------------------------

theme.border_width  = 2
theme.border_normal = p.border
theme.border_focus  = p.border
theme.border_hover  = p.accent
theme.border_marked = p.accent
theme.client_shape  = rounded(9)
theme.useless_gap   = 0

theme.titlebar_height    = 32
theme.titlebar_bg_focus  = p.surface
theme.titlebar_bg_normal = p.surface2
theme.titlebar_fg_focus  = p.fg
theme.titlebar_fg_normal = p.fg_dim

-- Title bar buttons: wide, flat, drawn as thin glyphs.
local BW, BH = 46, 32
local function button(glyph, fg, bg)
   return surface(BW, BH, function(cr, w, h)
      if bg then set_color(cr, bg); cr:paint() end
      set_color(cr, fg)
      cr:set_line_width(1)
      local cx, cy = math.floor(w / 2) + 0.5, math.floor(h / 2) + 0.5
      if glyph == "min" then
         cr:move_to(cx - 5, cy); cr:line_to(cx + 5, cy)
      elseif glyph == "max" then
         cr:translate(cx - 5, cy - 5); gears.shape.rounded_rect(cr, 10, 10, 1.5)
      elseif glyph == "restore" then
         cr:rectangle(cx - 5, cy - 3, 8, 8)
         cr:move_to(cx - 3, cy - 3); cr:line_to(cx - 3, cy - 5)
         cr:line_to(cx + 5, cy - 5); cr:line_to(cx + 5, cy + 3); cr:line_to(cx + 3, cy + 3)
      elseif glyph == "close" then
         cr:move_to(cx - 5, cy - 5); cr:line_to(cx + 5, cy + 5)
         cr:move_to(cx + 5, cy - 5); cr:line_to(cx - 5, cy + 5)
      end
      cr:stroke()
   end)
end

theme.titlebar_close_button_focus   = button("close", p.fg)
theme.titlebar_close_button_normal  = button("close", p.fg_dim)
theme.titlebar_close_button_hover   = button("close", "#ffffff", "#c42b1c")

theme.titlebar_minimize_button_focus  = button("min", p.fg)
theme.titlebar_minimize_button_normal = button("min", p.fg_dim)
theme.titlebar_minimize_button_hover  = button("min", p.fg, p.hover)
theme.titlebar_minimize_button_focus_inactive = theme.titlebar_minimize_button_focus

theme.titlebar_maximized_button_focus_inactive  = button("max", p.fg)
theme.titlebar_maximized_button_normal_inactive = button("max", p.fg_dim)
theme.titlebar_maximized_button_focus_active    = button("restore", p.fg)
theme.titlebar_maximized_button_normal_active   = button("restore", p.fg_dim)
theme.titlebar_maximized_button_hover           = button("max", p.fg, p.hover)

-- Taskbar ---------------------------------------------------------------

theme.bar_height   = 48
theme.bar_bg       = p.bar
theme.hover_bg     = p.hover
theme.active_bg    = p.active
theme.accent       = p.accent
theme.button_shape = rounded(6)

theme.tasklist_bg_normal   = "#00000000"
theme.tasklist_bg_focus    = p.active
theme.tasklist_bg_urgent   = "#c42b1c80"
theme.tasklist_bg_minimize = "#00000000"
theme.tasklist_shape       = rounded(6)
theme.tasklist_disable_task_name = true

theme.taglist_font        = theme.font_small
theme.taglist_fg_focus    = p.fg
theme.taglist_fg_empty    = p.fg_dim
theme.taglist_fg_occupied = p.fg
theme.taglist_bg_focus    = p.active
theme.taglist_bg_occupied = "#00000000"
theme.taglist_bg_empty    = "#00000000"
theme.taglist_shape       = rounded(5)
theme.taglist_spacing     = 2

-- Launcher button: a 3x3 grid of dots in the accent colour.
theme.start_icon = surface(48, 48, function(cr)
   set_color(cr, p.accent)
   for row = 0, 2 do
      for col = 0, 2 do
         cr:arc(13 + col * 11, 13 + row * 11, 3.4, 0, 2 * math.pi)
         cr:fill()
      end
   end
end)
theme.awesome_icon = theme.start_icon

-- Icons for the power menu, drawn as thin outlines in the text colour.
local function glyph(draw)
   return surface(48, 48, function(cr)
      set_color(cr, p.fg)
      cr:set_line_width(3)
      cr:set_line_cap(cairo.LineCap.ROUND)
      cr:set_line_join(cairo.LineJoin.ROUND)
      draw(cr)
   end)
end
theme.power_icon = glyph(function(cr)
   cr:arc(24, 26, 14, -math.pi / 2 + 0.6, -math.pi / 2 - 0.6 + 2 * math.pi); cr:stroke()
   cr:move_to(24, 8); cr:line_to(24, 24); cr:stroke()
end)
theme.lock_icon = glyph(function(cr)
   cr:arc(24, 19, 8, math.pi, 2 * math.pi); cr:stroke()
   cr:move_to(16, 19); cr:line_to(16, 23); cr:move_to(32, 19); cr:line_to(32, 23); cr:stroke()
   cr:translate(11, 23); gears.shape.rounded_rect(cr, 26, 18, 3); cr:stroke()
end)
theme.logout_icon = glyph(function(cr)
   cr:move_to(20, 10); cr:line_to(11, 10); cr:line_to(11, 38); cr:line_to(20, 38); cr:stroke()
   cr:move_to(20, 24); cr:line_to(38, 24); cr:stroke()
   cr:move_to(31, 17); cr:line_to(38, 24); cr:line_to(31, 31); cr:stroke()
end)
theme.restart_icon = glyph(function(cr)
   cr:arc(24, 24, 14, -math.pi / 2 + 0.9, -math.pi / 2 + 2 * math.pi); cr:stroke()
   cr:move_to(24, 4); cr:line_to(24, 16); cr:line_to(34, 10); cr:close_path(); cr:fill()
end)
theme.mode_icon = glyph(function(cr)
   cr:arc(24, 24, 14, 0, 2 * math.pi); cr:stroke()
   cr:arc(24, 24, 14, -math.pi / 2, math.pi / 2); cr:line_to(24, 10); cr:fill()
end)

-- Fallback icon for windows that do not provide one (e.g. the terminal).
theme.default_app_icon = surface(48, 48, function(cr)
   cr:translate(6, 9)
   gears.shape.rounded_rect(cr, 36, 30, 5)
   set_color(cr, MODE == "dark" and "#3a3a3a" or "#ffffff"); cr:fill_preserve()
   set_color(cr, p.fg_dim); cr:set_line_width(1.5); cr:stroke()
   set_color(cr, p.accent); cr:set_line_width(2.5)
   cr:move_to(8, 10); cr:line_to(14, 15); cr:line_to(8, 20); cr:stroke()
   cr:move_to(17, 21); cr:line_to(27, 21); cr:stroke()
end)

-- Menus -----------------------------------------------------------------

theme.menu_font         = theme.font
theme.menu_height       = 30
theme.menu_width        = 260
theme.menu_fg_normal    = p.fg
theme.menu_fg_focus     = p.fg
theme.menu_bg_normal    = p.menu
theme.menu_bg_focus     = p.active
theme.menu_border_width = 1
theme.menu_border_color = p.border
theme.menu_submenu_icon = surface(16, 16, function(cr)
   set_color(cr, p.fg_dim); cr:set_line_width(1.3)
   cr:move_to(6, 4); cr:line_to(10, 8); cr:line_to(6, 12); cr:stroke()
end)

theme.menubar_bg_normal = p.surface
theme.menubar_fg_normal = p.fg
theme.menubar_bg_focus  = p.accent
theme.menubar_fg_focus  = MODE == "dark" and "#000000" or "#ffffff"

theme.hotkeys_bg           = p.surface
theme.hotkeys_fg           = p.fg
theme.hotkeys_modifiers_fg = p.fg_dim
theme.hotkeys_border_color = p.border
theme.hotkeys_shape        = rounded(9)
theme.hotkeys_font         = "DejaVu Sans Mono Bold 9"
theme.hotkeys_description_font = "DejaVu Sans 9"

theme.tooltip_bg = p.surface2
theme.tooltip_fg = p.fg
theme.tooltip_border_color = p.border
theme.tooltip_border_width = 1
theme.tooltip_shape = rounded(4)

-- Notifications ---------------------------------------------------------

theme.notification_font         = theme.font
theme.notification_bg           = p.menu
theme.notification_fg           = p.fg
theme.notification_border_color = p.border
theme.notification_border_width = 1
theme.notification_shape        = rounded(8)
theme.notification_margin       = 14
naughty.config.defaults.position = "bottom_right"
naughty.config.defaults.margin   = 14
naughty.config.padding           = 12
naughty.config.spacing           = 8
naughty.config.presets.critical.bg = "#c42b1c"
naughty.config.presets.critical.fg = "#ffffff"

-- Network status icons used by the GoboNet widget: the stock neon icons,
-- recoloured to the theme's text colour.
local function mono(name)
   local ok, img = pcall(gears.color.recolor_image, dir .. name, p.fg)
   return ok and img or nil
end
theme.wifi_0_icon     = mono("wifi_0.png")
theme.wifi_1_icon     = mono("wifi_1.png")
theme.wifi_2_icon     = mono("wifi_2.png")
theme.wifi_3_icon     = mono("wifi_3.png")
theme.wifi_down_icon  = mono("wifi_down.png")
theme.wifi_up_icon    = mono("wifi_up.png")
theme.wired_up_icon   = mono("wired_up.png")
theme.wired_down_icon = mono("wired_down.png")
theme.check_icon      = mono("check.png")

for _, layout in ipairs({ "tile", "tileleft", "tilebottom", "tiletop", "fairv", "fairh",
                          "spiral", "dwindle", "max", "fullscreen", "magnifier", "floating" }) do
   theme["layout_" .. layout] = mono("layouts/" .. layout .. ".png")
end

-- Wallpaper: layered waves over a soft gradient, drawn at screen size.
theme.wallpaper = function(s)
   local geo = (type(s) == "number" and screen[s] or s).geometry
   local w, h = geo.width, geo.height
   return surface(w, h, function(cr)
      cr:set_source(gears.color({ type = "linear", from = { 0, 0 }, to = { w, h },
         stops = { { 0, p.wall_from }, { 1, p.wall_to } } }))
      cr:paint()

      local gx, gy = w * 0.70, h * 0.30
      cr:set_source(gears.color({ type = "radial", from = { gx, gy, 0 }, to = { gx, gy, w * 0.60 },
         stops = { { 0, p.glow .. "70" }, { 1, p.glow .. "00" } } }))
      cr:paint()

      local n = #p.waves
      for i, color in ipairs(p.waves) do
         local t = (i - 1) / (n - 1)
         local base = h * (0.50 + 0.36 * t)
         local amp = h * (0.16 - 0.09 * t)
         cr:move_to(0, h)
         for x = 0, w + 8, 8 do
            local u = x / w
            local y = base
               - amp * math.sin(u * math.pi * (1.1 + 0.5 * t) + 0.9 * i)
               - amp * 0.35 * math.sin(u * math.pi * 3.1 + 1.7 * i)
            cr:line_to(x, y)
         end
         cr:line_to(w, h)
         cr:close_path()
         cr:set_source(gears.color({ type = "linear", from = { 0, base - amp }, to = { w * 0.3, h },
            stops = { { 0, color .. "d8" }, { 1, color .. "70" } } }))
         cr:fill()
      end
   end)
end

return theme
