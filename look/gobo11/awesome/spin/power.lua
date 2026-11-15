-- Power menu: lock, log out, restart, shut down, plus the dark/light switch and (0.8.2)
-- the Settings app. A small card in the middle of the screen; Escape or a click outside
-- closes it.
--
-- 0.8.2: the menu can be used from the keyboard (power button, Win key path): Left/Right/Up/Down
-- (and Tab) move a visible selection, which starts on "Lock" (harmless; Enter alone never shuts
-- down); Enter (or Space) runs the selected entry; Escape closes. Mouse and selection are one:
-- hovering an entry selects it.

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local menubar = require("menubar")
local popups = require("spin.popups")

local power = {}

local config_dir = gears.filesystem.get_configuration_dir()
local grabber         -- the key grabber function while the menu is open
local popup, backdrop
local open = false

function power.lock()
   awful.spawn.with_shell("sh " .. config_dir .. "lock.sh")
end

-- Shutting down needs root. The installer adds a sudo rule that lets members
-- of the "sys" group run exactly these commands without a password.
local function system(command)
   awful.spawn.with_shell("sudo -n /System/Index/bin/" .. command)
end

function power.toggle_mode()
   local new = (beautiful.mode == "light") and "dark" or "light"
   awful.spawn.easy_async_with_shell("sh " .. config_dir .. "set-mode.sh " .. new, function()
      -- 0.8.1: come back to the same desktop after the restart (rc.lua reads this file)
      local t = awful.screen.focused().selected_tag
      local f = t and io.open((os.getenv("HOME") or "") .. "/.cache/awesome-restart-desktop", "w")
      if f then f:write(tostring(t.index)); f:close() end
      awesome.restart()
   end)
end

local function entries()
   local list = {
      { "Lock", beautiful.lock_icon, power.lock },
      { "Log out", beautiful.logout_icon, function() awesome.quit() end },
      { "Restart", beautiful.restart_icon, function() system("shutdown -r now") end },
      { "Shut down", beautiful.power_icon, function() system("shutdown -h now") end },
      { (beautiful.mode == "light") and "Dark mode" or "Light mode", beautiful.mode_icon, power.toggle_mode },
   }
   -- 0.8.2: the Settings app (spin/settings), when the image has it
   if gears.filesystem.file_readable("/System/Index/bin/gobo-settings") then
      table.insert(list, { "Settings", menubar.utils.lookup_icon("preferences-system") or beautiful.mode_icon,
         function() awful.spawn("gobo-settings") end })
   end
   return list
end

local buttons, actions = {}, {}
local sel

local function select(i)
   if sel and buttons[sel] then
      buttons[sel].bg = nil
      buttons[sel].shape_border_width = 0
   end
   sel = i
   if sel and buttons[sel] then
      buttons[sel].bg = beautiful.hover_bg
      buttons[sel].shape_border_width = 2
      buttons[sel].shape_border_color = beautiful.accent
   end
end
power.select = select                          -- lab tests
function power.selected() return sel end       -- lab tests
function power.is_open() return open end       -- lab tests

function power.hide()
   if not open then return end
   open = false
   select(nil)
   popup.visible = false
   backdrop.visible = false
   -- awful.keygrabber, not the bare C keygrabber: mixing the two leaves awful's
   -- grabber stack out of step and breaks keyboard input in the search later.
   if grabber then awful.keygrabber.stop(grabber); grabber = nil end
end

local function run(i)
   local action = actions[i]
   power.hide()
   if action then action() end
end

local function build()
   local row = wibox.layout.fixed.horizontal()
   row.spacing = 8
   for i, entry in ipairs(entries()) do
      local label, icon, action = entry[1], entry[2], entry[3]
      local button = wibox.widget {
         {
            {
               {
                  { image = icon, forced_width = 30, forced_height = 30, widget = wibox.widget.imagebox },
                  halign = "center", widget = wibox.container.place,
               },
               { text = label, align = "center", font = beautiful.font_small, widget = wibox.widget.textbox },
               spacing = 10,
               layout = wibox.layout.fixed.vertical,
            },
            left = 8, right = 8, top = 14, bottom = 12,
            widget = wibox.container.margin,
         },
         forced_width = 96,
         shape = beautiful.button_shape,
         widget = wibox.container.background,
      }
      buttons[i], actions[i] = button, action
      button:connect_signal("mouse::enter", function() select(i) end)
      button:connect_signal("mouse::leave", function() if sel == i then select(nil) end end)
      button:buttons(awful.button({}, 1, function() run(i) end))
      row:add(button)
   end

   local n = #buttons
   popup = wibox({
      width = n * 96 + (n - 1) * 8 + 28, height = 118, ontop = true, visible = false,
      bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
      border_width = 1, border_color = beautiful.menu_border_color,
      shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 10) end,
      type = "popup_menu",
   })
   popup:setup { row, margins = 14, widget = wibox.container.margin }

   backdrop = popups.backdrop(power.hide, "#00000066", function() return popup ~= nil and popup.visible end)
end

function power.show()
   if not popup then build() end
   if open then power.hide(); return end
   popups.close_all("power")
   open = true
   local s = awful.screen.focused()
   popup.x = s.geometry.x + math.floor((s.geometry.width - popup.width) / 2)
   popup.y = s.geometry.y + math.floor((s.geometry.height - popup.height) / 2)
   backdrop.show_on(s)
   popup.visible = true
   -- 0.8.2 part 2: "Lock" (harmless) is selected when the menu opens, so the selection is
   -- visible from the start and the first arrow key moves from there; Enter alone locks
   select(1)
   grabber = awful.keygrabber.run(function(_, key, event)
      if event ~= "press" then return end
      local n = #buttons
      if key == "Escape" or key == "q" then
         power.hide()
      elseif key == "Right" or key == "Down" or key == "Tab" then
         select(sel and (sel % n + 1) or 1)
      elseif key == "Left" or key == "Up" or key == "ISO_Left_Tab" then
         select(sel and ((sel - 2) % n + 1) or n)
      elseif key == "Home" then
         select(1)
      elseif key == "End" then
         select(n)
      elseif (key == "Return" or key == "KP_Enter" or key == "space") and sel then
         -- after this key event, so the action's window does not get the Enter
         local i = sel
         gears.timer.delayed_call(function() run(i) end)
      end
   end)
end

popups.register("power", power.hide)

return power
