-- Power menu: lock, log out, restart, shut down, plus the dark/light switch.
-- A small card in the middle of the screen; Escape or a click outside closes it.

local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
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
      awesome.restart()
   end)
end

local function entries()
   return {
      { "Lock", beautiful.lock_icon, power.lock },
      { "Log out", beautiful.logout_icon, function() awesome.quit() end },
      { "Restart", beautiful.restart_icon, function() system("shutdown -r now") end },
      { "Shut down", beautiful.power_icon, function() system("shutdown -h now") end },
      { (beautiful.mode == "light") and "Dark mode" or "Light mode", beautiful.mode_icon, power.toggle_mode },
   }
end

function power.hide()
   if not open then return end
   open = false
   popup.visible = false
   backdrop.visible = false
   -- awful.keygrabber, not the bare C keygrabber: mixing the two leaves awful's
   -- grabber stack out of step and breaks keyboard input in the search later.
   if grabber then awful.keygrabber.stop(grabber); grabber = nil end
end

local function build()
   local row = wibox.layout.fixed.horizontal()
   row.spacing = 8
   for _, entry in ipairs(entries()) do
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
      button:connect_signal("mouse::enter", function() button.bg = beautiful.hover_bg end)
      button:connect_signal("mouse::leave", function() button.bg = nil end)
      button:buttons(awful.button({}, 1, function() power.hide(); action() end))
      row:add(button)
   end

   popup = wibox({
      width = 5 * 96 + 4 * 8 + 28, height = 118, ontop = true, visible = false,
      bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
      border_width = 1, border_color = beautiful.menu_border_color,
      shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 10) end,
      type = "popup_menu",
   })
   popup:setup { row, margins = 14, widget = wibox.container.margin }

   backdrop = popups.backdrop(power.hide, "#00000066")
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
   grabber = awful.keygrabber.run(function(_, key, event)
      if event == "press" and (key == "Escape" or key == "q") then power.hide() end
   end)
end

popups.register("power", power.hide)

return power
