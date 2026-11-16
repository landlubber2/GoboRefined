-- Flat status icons for the taskbar: battery, volume and screen brightness.
-- They replace the stock GoboLinux widgets (same behaviour, drawn in the
-- theme's colours instead of the neon style).

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local beautiful = require("beautiful")
local cairo = require("lgi").cairo

local status = {}

local SIZE = 48 -- icons are drawn on a 48x48 canvas and scaled by the bar

local function color(cr, hex, alpha)
   local r, g, b, a = gears.color.parse_color(hex)
   cr:set_source_rgba(r, g, b, alpha or a)
end

local function canvas(draw)
   local img = cairo.ImageSurface("ARGB32", SIZE, SIZE)
   local cr = cairo.Context(img)
   cr:set_line_width(3)
   cr:set_line_cap(cairo.LineCap.ROUND)
   cr:set_line_join(cairo.LineJoin.ROUND)
   draw(cr)
   return img
end

local function read_first_line(path)
   local fd = io.open(path, "r")
   if not fd then return nil end
   local line = fd:read("*l")
   fd:close()
   return line
end

local function pread(cmd)
   local pd = io.popen(cmd, "r")
   if not pd then return "" end
   local data = pd:read("*a")
   pd:close()
   return data
end

-- Battery ---------------------------------------------------------------

local function battery_state()
   local base = "/sys/class/power_supply"
   local pd = io.popen("ls " .. base .. " 2>/dev/null")
   if not pd then return nil end
   for name in pd:lines() do
      local capacity = tonumber(read_first_line(base .. "/" .. name .. "/capacity") or "")
      if capacity then
         pd:close()
         return { percent = capacity, mode = read_first_line(base .. "/" .. name .. "/status") or "" }
      end
   end
   pd:close()
   return nil
end

local function battery_icon(state)
   local fg = beautiful.fg_normal
   return canvas(function(cr)
      -- body and terminal
      color(cr, fg)
      gears.shape.transform(gears.shape.rounded_rect):translate(5, 14)(cr, 34, 20, 4)
      cr:stroke()
      cr:rectangle(41, 20, 3, 8)
      cr:fill()
      -- charge level
      local low = state.percent <= 15 and state.mode ~= "Charging"
      color(cr, low and "#e5484d" or (state.mode == "Charging" and "#3fb950" or fg))
      local w = math.max(2, 26 * state.percent / 100)
      gears.shape.transform(gears.shape.rounded_rect):translate(9, 18)(cr, w, 12, 1.5)
      cr:fill()
      if state.mode == "Charging" then
         color(cr, beautiful.palette and beautiful.palette.surface or "#202020")
         cr:move_to(24, 15); cr:line_to(18, 25); cr:line_to(23, 25)
         cr:line_to(20, 33); cr:line_to(27, 22); cr:line_to(22, 22)
         cr:close_path()
         cr:fill()
      end
   end)
end

function status.battery()
   local widget = wibox.widget.imagebox()
   local state = battery_state()
   if not state then return widget end -- no battery: an empty widget

   local tip = awful.tooltip({ objects = { widget } })
   local warned = {}
   local function refresh()
      state = battery_state() or state
      widget:set_image(battery_icon(state))
      tip.text = string.format("Battery %d%%%s", state.percent,
         state.mode == "Charging" and ", charging" or "")
      if state.mode == "Charging" then
         warned = {}
      else
         for _, level in ipairs({ 15, 10, 5 }) do
            if state.percent <= level and not warned[level] then
               warned[level] = true
               naughty.notify({ title = "Battery low", text = state.percent .. "% left", timeout = 8 })
               break
            end
         end
      end
   end
   refresh()
   gears.timer({ timeout = 20, autostart = true, callback = refresh })
   return widget
end

-- Volume ----------------------------------------------------------------

local function volume_icon(state)
   local fg = beautiful.fg_normal
   return canvas(function(cr)
      color(cr, fg)
      -- speaker
      cr:move_to(8, 20); cr:line_to(15, 20); cr:line_to(24, 12)
      cr:line_to(24, 36); cr:line_to(15, 28); cr:line_to(8, 28)
      cr:close_path()
      cr:fill()
      if state.mute or not state.valid then
         color(cr, "#e5484d")
         cr:move_to(31, 18); cr:line_to(41, 30)
         cr:move_to(41, 18); cr:line_to(31, 30)
         cr:stroke()
      else
         -- one to three sound waves, faded when the level is below them
         for i, level in ipairs({ 1, 34, 67 }) do
            color(cr, fg, state.volume >= level and 1 or 0.25)
            cr:arc(24, 24, 5 + i * 5.5, -math.pi / 3.4, math.pi / 3.4)
            cr:stroke()
         end
      end
   end)
end

-- mixer: command for the sound control window (opened by a left click)
function status.volume(mixer)
   local widget = wibox.widget.imagebox()
   local state = { valid = false, volume = 0, mute = false, sink = "0" }
   local tip = awful.tooltip({ objects = { widget } })

   local function parse(output)
      local volume = output:match("volume: front.-([0-9]*)%%")
      local mute = output:match("muted: ([yesno]*)")
      state.valid = (volume ~= nil and mute ~= nil)
      if state.valid then
         state.sink = output:match("%* index: ([0-9]*)") or state.sink
         state.volume = tonumber(volume) or 0
         state.mute = (mute == "yes")
      end
      widget:set_image(volume_icon(state))
      tip.text = not state.valid and "No sound device"
         or (state.mute and "Muted" or ("Volume " .. state.volume .. "%"))
   end
   local function refresh(command)
      parse(pread((command and (command .. "; ") or "") .. "pacmd list-sinks 2>/dev/null"))
   end

   function widget:set_volume(val, delta)
      local volume = state.volume
      if delta == "+" then volume = math.min(volume + val, 100)
      elseif delta == "-" then volume = math.max(0, volume - val)
      else volume = val end
      refresh("pactl set-sink-volume " .. state.sink .. " " .. volume .. "%")
   end
   function widget:toggle_mute()
      refresh("pactl set-sink-mute " .. state.sink .. " " .. (state.mute and "no" or "yes"))
   end

   -- 0.8.5: right click = a menu of the outputs (speakers, headphones, HDMI, Bluetooth) to switch
   -- between (what is playing moves along), mute, and Settings > Sound
   local menu
   local function output_menu()
      if menu and menu.wibox.visible then menu:hide() menu = nil return end
      local text = pread("LC_ALL=C pactl info 2>/dev/null; LC_ALL=C pactl list sinks 2>/dev/null")
      local default = text:match("Default Sink: (%S+)")
      local items = {}
      for name, desc in text:gmatch("\n\tName: (%S+)\n\tDescription: ([^\n]+)") do
         if name ~= "auto_null" then
            table.insert(items, { (name == default and "● " or "    ") .. desc, function()
               local q = "'" .. name:gsub("'", "") .. "'"
               awful.spawn.with_shell("pactl set-default-sink " .. q .. " && for i in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input $i " .. q .. "; done")
            end })
         end
      end
      if #items == 0 then table.insert(items, { "No sound output", function() end }) end
      table.insert(items, { state.mute and "Unmute" or "Mute", function() widget:toggle_mute() end })
      table.insert(items, { "Sound settings...", function() awful.spawn({ "gobo-settings", "sound" }) end })
      menu = awful.menu({ items = items, theme = { width = 300 } })
      menu:show()
   end

   widget:buttons(awful.util.table.join(
      awful.button({}, 1, function()
         awful.spawn(mixer or "urxvt -title ncpamixer -geometry 90x18 -e ncpamixer")
      end),
      awful.button({}, 2, function() widget:toggle_mute() end),
      awful.button({}, 3, function() output_menu() end),
      awful.button({}, 4, function() widget:set_volume(5, "+") end),
      awful.button({}, 5, function() widget:set_volume(5, "-") end)
   ))
   refresh()
   gears.timer({ timeout = 5, autostart = true, callback = function() refresh() end })
   return widget
end

-- Brightness ------------------------------------------------------------

local function brightness_icon()
   local fg = beautiful.fg_normal
   return canvas(function(cr)
      color(cr, fg)
      cr:arc(24, 24, 7, 0, 2 * math.pi)
      cr:fill()
      for i = 0, 7 do
         local a = i * math.pi / 4
         cr:move_to(24 + 12 * math.cos(a), 24 + 12 * math.sin(a))
         cr:line_to(24 + 16 * math.cos(a), 24 + 16 * math.sin(a))
      end
      cr:stroke()
   end)
end

function status.brightness()
   local widget = wibox.widget.imagebox()
   local level = tonumber(pread("gobolight 2>/dev/null"):match("^(%d+)") or "")
   local tip = awful.tooltip({ objects = { widget } })

   local function run(args)
      local value = tonumber(pread("gobolight " .. args .. " 2>/dev/null"):match("^(%d+)") or "")
      if value then
         level = value
         tip.text = "Brightness " .. level .. "%"
      end
   end
   function widget:inc_brightness(val) if level then run("-inc " .. val) end end
   function widget:dec_brightness(val) if level then run("-dec " .. math.min(val, level - 1)) end end

   if not level then return widget end -- no adjustable backlight (desktop PC, VM): stay empty
   widget:set_image(brightness_icon())
   tip.text = "Brightness " .. level .. "%"
   widget:buttons(awful.util.table.join(
      awful.button({}, 4, function() widget:inc_brightness(5) end),
      awful.button({}, 5, function() widget:dec_brightness(5) end)
   ))
   return widget
end

return status
