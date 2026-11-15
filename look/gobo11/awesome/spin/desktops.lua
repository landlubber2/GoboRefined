-- Virtual desktops (0.6): one desktop per screen to start with; Win+Shift+Tab opens a list
-- of the desktops (number + the windows on each) with "Add desktop" and a remove button.
--   keys in the list: Tab / Down / Right = next, Shift+Tab / Up / Left = previous,
--   Enter = go there (or add), Delete = remove the selected desktop, 1-9 = go to desktop N,
--   Escape = close. Mouse: click a row, the "x" on a row, or "Add desktop".
-- Removing a desktop moves its windows to the neighbouring one (the previous, or the next
-- for the first). The last remaining desktop cannot be removed.
-- The number of desktops per screen is saved (~/.cache/awesome/spin-desktops) and every
-- window remembers its desktop in an X property, so an Awesome restart (the light/dark
-- switch does one) keeps windows where they were.
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local popups = require("spin.popups")

local desktops = {}

local STATE = gears.filesystem.get_cache_dir() .. "spin-desktops"
local MAX = 9
local layout_default
local on_change = {}   -- callbacks after desktops were added/removed (taskbar indicator)

awesome.register_xproperty("_SPIN_DESKTOP", "number")

-- saved counts: { [screen index] = n }
local function load_counts()
   local counts = {}
   local f = io.open(STATE, "r")
   if f then
      for line in f:lines() do
         local s, n = line:match("^(%d+)%s+(%d+)")
         if s then counts[tonumber(s)] = math.max(1, math.min(MAX, tonumber(n))) end
      end
      f:close()
   end
   return counts
end

local function save_counts()
   local f = io.open(STATE, "w")
   if not f then return end
   for s in screen do f:write(s.index, " ", #s.tags, "\n") end
   f:close()
end

local function renumber(s)
   for i, t in ipairs(s.tags) do t.name = tostring(i) end
end

local function changed(s)
   renumber(s)
   save_counts()
   for _, fn in ipairs(on_change) do fn(s) end
end

function desktops.on_change(fn) table.insert(on_change, fn) end

-- create the desktops of a screen (call from connect_for_each_screen)
function desktops.setup_screen(s, layout)
   layout_default = layout_default or layout
   local n = load_counts()[s.index] or 1
   local names = {}
   for i = 1, n do names[i] = tostring(i) end
   awful.tag(names, s, layout)
end

-- remember each window's desktop (index on its screen) across restarts
local function remember(c)
   if not c.valid then return end
   local t = c.first_tag
   if t and t.index then c:set_xproperty("_SPIN_DESKTOP", t.index) end
end
client.connect_signal("tagged", remember)
client.connect_signal("untagged", remember)
client.connect_signal("manage", function(c)
   if not awesome.startup then return remember(c) end
   local i = c:get_xproperty("_SPIN_DESKTOP")
   local tags = c.screen.tags
   if i and tags[i] then c:move_to_tag(tags[i]) end
end)

function desktops.add(s)
   s = s or awful.screen.focused()
   if #s.tags >= MAX then return nil end
   local t = awful.tag.add(tostring(#s.tags + 1), { screen = s, layout = layout_default or awful.layout.suit.floating })
   changed(s)
   return t
end

function desktops.remove(t)
   local s = t.screen
   if #s.tags <= 1 then return false end
   local idx = t.index
   local to = s.tags[idx - 1] or s.tags[idx + 1]
   for _, c in ipairs(t:clients()) do
      c:move_to_tag(to)
   end
   local was_selected = t.selected
   t:delete(to, true)
   if was_selected then to:view_only() end
   changed(s)
   return true
end

function desktops.view(i, s)
   s = s or awful.screen.focused()
   local t = s.tags[i]
   if t then t:view_only() end
   return t
end

-- Popup -----------------------------------------------------------------------------

local W, ROW_H = 420, 52
local popup, backdrop, rows_layout
local grabber
local sel = 1
local cur_screen
local open = false

local function p() return beautiful.palette end

local function client_icon(c)
   return c.icon or (desktops.icon_for and desktops.icon_for(c)) or beautiful.default_app_icon
end

local redraw

local function activate(i)
   local s = cur_screen
   desktops.hide()
   if i == #s.tags + 1 then
      local t = desktops.add(s)
      if t then t:view_only() end
   else
      desktops.view(i, s)
   end
end

local function remove_at(i)
   local t = cur_screen.tags[i]
   if t and desktops.remove(t) then
      sel = math.min(sel, #cur_screen.tags + 1)
      redraw()
   end
end

local remove_clicked = false

local function hover(w, i)
   w:connect_signal("mouse::enter", function() if sel ~= i then sel = i; redraw() end end)
end

local function row_widget(i, t)
   local s = cur_screen
   local icons = wibox.layout.fixed.horizontal()
   icons.spacing = 4
   local names = {}
   local cls = {}
   -- 0.8.1: not the desktop window (PCManFM --desktop, listed as "Pcmanfm" on every desktop)
   for _, c in ipairs(t and t:clients() or {}) do
      if c.type ~= "desktop" then table.insert(cls, c) end
   end
   for k, c in ipairs(cls) do
      if k <= 5 then
         icons:add(wibox.widget { image = client_icon(c), forced_width = 20, forced_height = 20,
            widget = wibox.widget.imagebox })
      end
      table.insert(names, c.class or c.name or "?")
   end
   local label, detail
   if t then
      label = "Desktop " .. i .. (t.selected and "  (current)" or "")
      detail = #cls == 0 and "empty" or table.concat(names, ", ")
   else
      label = (#s.tags >= MAX) and "Add desktop (at most 9)" or "+  Add desktop"
      detail = "a new empty desktop"
   end
   local text = wibox.widget {
      { text = label, font = beautiful.font, widget = wibox.widget.textbox },
      { markup = '<span foreground="' .. p().fg_dim .. '">' .. gears.string.xml_escape(detail) .. '</span>',
        font = beautiful.font_small, ellipsize = "end", forced_height = 16, widget = wibox.widget.textbox },
      layout = wibox.layout.fixed.vertical,
   }
   local remove
   if t and #s.tags > 1 then
      remove = wibox.widget {
         { { text = "×", font = "Inter 13", align = "center", widget = wibox.widget.textbox },
           margins = 2, widget = wibox.container.margin },
         forced_width = 30, forced_height = 30, shape = beautiful.button_shape,
         widget = wibox.container.background,
      }
      remove:connect_signal("mouse::enter", function() remove.bg = "#c42b1c"; remove.fg = "#ffffff" end)
      remove:connect_signal("mouse::leave", function() remove.bg = nil; remove.fg = nil end)
      remove:buttons(awful.button({}, 1, function() remove_clicked = true end,
         function() remove_at(i) end))
   end
   text.forced_width = W - 28 - 22 - 5 * 24 - 40
   local right = wibox.layout.fixed.horizontal()
   right.spacing = 8
   right:add(wibox.container.place(icons))
   if remove then right:add(wibox.container.place(remove)) end
   local row = wibox.widget {
      {
         text, nil, right,
         layout = wibox.layout.align.horizontal,
      },
      left = 14, right = 8, top = 7, bottom = 7,
      widget = wibox.container.margin,
   }
   row = wibox.widget {
      row,
      forced_height = ROW_H,
      bg = (i == sel) and beautiful.active_bg or nil,
      shape = beautiful.button_shape,
      widget = wibox.container.background,
   }
   hover(row, i)
   -- both the row and its remove button see a click on the button: the button wins
   row:buttons(awful.button({}, 1, nil, function()
      if remove_clicked then remove_clicked = false; return end
      activate(i)
   end))
   return row
end

redraw = function()
   if not popup then return end
   rows_layout:reset()
   local s = cur_screen
   for i, t in ipairs(s.tags) do rows_layout:add(row_widget(i, t)) end
   rows_layout:add(row_widget(#s.tags + 1, nil))
   local n = #s.tags + 1
   popup.height = 14 + 30 + n * (ROW_H + 4) + 14 + 22
   local g = s.geometry
   popup.x = g.x + math.floor((g.width - W) / 2)
   popup.y = g.y + math.floor((g.height - popup.height) / 2)
end

local function build()
   rows_layout = wibox.layout.fixed.vertical()
   rows_layout.spacing = 4
   popup = wibox({
      width = W, height = 200, ontop = true, visible = false,
      bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
      border_width = 1, border_color = beautiful.menu_border_color,
      shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 10) end,
      type = "popup_menu",
   })
   popup:setup {
      {
         { { text = "Desktops", font = beautiful.font_title or beautiful.font, widget = wibox.widget.textbox },
           bottom = 10, widget = wibox.container.margin },
         rows_layout,
         { { markup = '<span foreground="' .. p().fg_dim .. '">Enter: go there. x or Delete: remove (windows move next door)</span>',
             font = beautiful.font_small, align = "center", widget = wibox.widget.textbox },
           top = 8, widget = wibox.container.margin },
         layout = wibox.layout.fixed.vertical,
      },
      margins = 14, widget = wibox.container.margin,
   }
   backdrop = popups.backdrop(function() desktops.hide() end)
end

function desktops.hide()
   if not open then return end
   open = false
   popup.visible = false
   backdrop.visible = false
   if grabber then awful.keygrabber.stop(grabber); grabber = nil end
end

function desktops.show()
   if not popup then build() end
   if open then
      -- Win+Shift+Tab again while open: next entry
      sel = sel % (#cur_screen.tags + 1) + 1
      redraw()
      return
   end
   popups.close_all("desktops")
   open = true
   cur_screen = awful.screen.focused()
   local t = cur_screen.selected_tag
   sel = t and t.index or 1
   redraw()
   backdrop.show_on(cur_screen)
   popup.visible = true
   grabber = awful.keygrabber.run(function(mods, key, event)
      if event ~= "press" then return end
      local n = #cur_screen.tags + 1
      local shift = false
      for _, m in ipairs(mods) do if m == "Shift" then shift = true end end
      if key == "Escape" then desktops.hide()
      elseif key == "Return" or key == "KP_Enter" or key == "space" then activate(sel)
      elseif key == "Delete" or key == "BackSpace" then remove_at(sel)
      elseif ((key == "Tab" or key == "ISO_Left_Tab") and shift) or key == "Up" or key == "Left" then
         sel = (sel - 2) % n + 1; redraw()
      elseif key == "Tab" or key == "Down" or key == "Right" then
         sel = sel % n + 1; redraw()
      elseif key:match("^%d$") and tonumber(key) >= 1 and tonumber(key) <= #cur_screen.tags then
         activate(tonumber(key))
      end
   end)
end

popups.register("desktops", desktops.hide)

return desktops
