-- 0.9.6: a small right-click menu (one to three entries: "Pin to start", "Unpin", ...) that opens
-- ON TOP of the start menu, the frequently-used panel or the search without closing them. It is
-- not an awful.menu: showing an awful.menu closes every other popup (spin/popups.lua).
-- It closes when an entry is chosen, when its owner closes (the owner calls ctxmenu.hide()), when
-- another popup opens (registered with popups) and on Escape inside the owner's own grab.
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local popups = require("spin.popups")

local M = {}
local box
local ROW_H, WIDTH = 32, 190

function M.hide()
   if box then box.visible = false end
end

function M.is_open() return box ~= nil and box.visible end

-- items: { { label, function }, ... } ; x, y: where (default: the mouse pointer)
function M.show(items, x, y)
   if not items or #items == 0 then return end
   if not box then
      box = wibox({ ontop = true, visible = false, type = "popup_menu",
         bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
         border_width = 1, border_color = beautiful.menu_border_color,
         shape = beautiful.menu_shape })
   end
   M.hide()
   local list = wibox.layout.fixed.vertical()
   for _, it in ipairs(items) do
      local row = wibox.widget {
         { { text = it[1], font = beautiful.font, widget = wibox.widget.textbox },
           left = 14, right = 14, widget = wibox.container.margin },
         forced_height = ROW_H, widget = wibox.container.background,
      }
      row:connect_signal("mouse::enter", function() row.bg = beautiful.hover_bg end)
      row:connect_signal("mouse::leave", function() row.bg = nil end)
      row:buttons(awful.button({}, 1, nil, function()
         M.hide()
         local ok, err = pcall(it[2])
         if not ok then io.stderr:write("ctxmenu: " .. tostring(err) .. "\n") end
      end))
      list:add(row)
   end
   box:set_widget(wibox.container.margin(list, 0, 0, 4, 4))
   local m = mouse.coords()
   x, y = x or m.x, y or m.y
   local h = #items * ROW_H + 8
   local g = (awful.screen.focused() or screen.primary).geometry
   x = math.max(g.x, math.min(x, g.x + g.width - WIDTH - 2))
   y = math.max(g.y, math.min(y, g.y + g.height - h - 2))
   box:geometry({ x = x, y = y, width = WIDTH, height = h })
   box.visible = true   -- mapped last, so it is stacked above the menu and its click sheet
end

popups.register("ctxmenu", M.hide)

return M
