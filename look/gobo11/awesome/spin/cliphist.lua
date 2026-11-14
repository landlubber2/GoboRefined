-- Clipboard history (0.6). CopyQ (started from ~/.xinitrc, 20 items, no tray icon) keeps
-- the last copied texts and pictures, also after the program they came from has closed.
-- Win+Shift+V shows them in a popup in the look's style; picking one puts it back on the
-- clipboard and pastes it into the window that had the focus (Ctrl+V, or Ctrl+Shift+V in
-- the terminal; pictures are not pasted into a terminal, only put on the clipboard).
--   keys: Up/Down (or Tab), Enter, Delete = forget the entry, Escape. Mouse: click a row.
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local beautiful = require("beautiful")
local popups = require("spin.popups")

local cliphist = {}

local W, ROW_H, MAX_ROWS = 560, 44, 10
local THUMBS = "/tmp/spin-cliphist-" .. (os.getenv("USER") or "user")
local popup, backdrop, list_layout, hint, grabber
local items = {}        -- { index, kind = "text"|"image", text, thumb }
local sel, offset = 1, 0
local target            -- the window that had the focus
local open = false

local function p() return beautiful.palette end

-- One CopyQ script call lists the items: "index<TAB>kind<TAB>preview" per line, and writes
-- the pictures to $THUMBS/<index>.png for the preview.
-- (No backslashes in it: copyq unescapes its command-line arguments, so '\n' would arrive
-- as a real line break inside a string and break the script.)
local LIST_SCRIPT = [[
var dir = arguments[1];
var NL = String.fromCharCode(10), TAB = String.fromCharCode(9), CR = String.fromCharCode(13);
var space = new RegExp('[ ' + TAB + NL + CR + ']+', 'g');
var out = '';
for (var i = 0; i < Math.min(size(), 20); ++i) {
  var formats = str(read('?', i));
  var kind = 'text', text = '';
  if (formats.indexOf('image/png') >= 0) {
    kind = 'image';
    var f = new File(dir + '/' + i + '.png');
    if (f.openWriteOnly()) { f.write(read('image/png', i)); f.close(); }
  } else {
    text = str(read(i)).replace(space, ' ').substring(0, 160);
  }
  out += i + TAB + kind + TAB + text + NL;
}
out
]]


local function load(cb)
   awful.spawn.easy_async({ "mkdir", "-p", THUMBS }, function()
      awful.spawn.easy_async({ "copyq", "eval", LIST_SCRIPT, THUMBS }, function(out, err, _, code)
         items = {}
         cliphist.last_error = (code ~= 0) and err or nil
         if code == 0 then
            for line in out:gmatch("[^\n]+") do
               local i, kind, text = line:match("^(%d+)\t(%a+)\t(.*)$")
               if i then
                  table.insert(items, { index = tonumber(i), kind = kind, text = text,
                     thumb = kind == "image" and (THUMBS .. "/" .. i .. ".png") or nil })
               end
            end
         end
         cb(code == 0)
      end)
   end)
end

local redraw

local function paste_into(c, kind)
   if not (c and c.valid) then return end
   client.focus = c
   c:raise()
   local class = (c.class or ""):lower()
   local terminal = class == "urxvt" or class == "xterm" or class:match("term") ~= nil
   if terminal and kind == "image" then return end
   gears.timer.start_new(0.15, function()
      local keys = terminal and { "Control_L", "Shift_L", "v" } or { "Control_L", "v" }
      for _, k in ipairs(keys) do root.fake_input("key_press", k) end
      for i = #keys, 1, -1 do root.fake_input("key_release", keys[i]) end
      return false
   end)
end

local function pick(i)
   local item = items[i]
   local c = target
   cliphist.hide()
   if not item then return end
   -- select() moves the item to the top and puts it on the clipboard
   awful.spawn.easy_async({ "copyq", "select", tostring(item.index) }, function(_, _, _, code)
      if code == 0 then paste_into(c, item.kind) end
   end)
end

local function forget(i)
   local item = items[i]
   if not item then return end
   awful.spawn.easy_async({ "copyq", "remove", tostring(item.index) }, function()
      load(function()
         sel = math.max(1, math.min(sel, #items))
         redraw()
      end)
   end)
end

local function move(d)
   if #items == 0 then return end
   sel = math.max(1, math.min(#items, sel + d))
   if sel <= offset then offset = sel - 1 end
   if sel > offset + MAX_ROWS then offset = sel - MAX_ROWS end
   redraw()
end

redraw = function()
   list_layout:reset()
   for i = offset + 1, math.min(#items, offset + MAX_ROWS) do
      local it = items[i]
      local content
      if it.kind == "image" then
         content = wibox.widget {
            { image = gears.surface.load_uncached_silently(it.thumb), forced_height = 32, forced_width = 64,
              resize = true, widget = wibox.widget.imagebox },
            { text = "Picture", font = beautiful.font, widget = wibox.widget.textbox },
            spacing = 12, layout = wibox.layout.fixed.horizontal,
         }
      else
         content = wibox.widget { text = it.text ~= "" and it.text or "(empty)", font = beautiful.font,
            ellipsize = "end", forced_height = 20, widget = wibox.widget.textbox }
      end
      local row = wibox.widget {
         { { content, valign = "center", halign = "left", widget = wibox.container.place },
           left = 14, right = 14, top = 6, bottom = 6, widget = wibox.container.margin },
         forced_height = ROW_H,
         bg = (i == sel) and beautiful.active_bg or nil,
         shape = beautiful.button_shape,
         widget = wibox.container.background,
      }
      row:connect_signal("mouse::enter", function() if sel ~= i then sel = i; redraw() end end)
      row:buttons(awful.button({}, 1, nil, function() pick(i) end))
      list_layout:add(row)
   end
   if #items == 0 then
      list_layout:add(wibox.widget { text = "Nothing copied yet.", align = "center", font = beautiful.font,
         forced_height = ROW_H, widget = wibox.widget.textbox })
   end
   hint.markup = '<span foreground="' .. p().fg_dim .. '">'
      .. (#items > MAX_ROWS and string.format("%d of %d  -  ", sel, #items) or "")
      .. "Enter pastes, Delete forgets, Esc closes</span>"
   local rows = math.max(1, math.min(#items, MAX_ROWS))
   popup.height = 14 + 30 + rows * (ROW_H + 2) + 30 + 14
   local s = awful.screen.focused()
   popup.x = s.geometry.x + math.floor((s.geometry.width - W) / 2)
   popup.y = s.geometry.y + math.floor((s.geometry.height - popup.height) / 2)
end

local function build()
   list_layout = wibox.layout.fixed.vertical()
   list_layout.spacing = 2
   hint = wibox.widget { font = beautiful.font_small, align = "center", widget = wibox.widget.textbox }
   popup = wibox({
      width = W, height = 200, ontop = true, visible = false,
      bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
      border_width = 1, border_color = beautiful.menu_border_color,
      shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 10) end,
      type = "popup_menu",
   })
   popup:setup {
      {
         { { text = "Clipboard history", font = beautiful.font_title or beautiful.font, widget = wibox.widget.textbox },
           bottom = 10, widget = wibox.container.margin },
         list_layout,
         { hint, top = 10, widget = wibox.container.margin },
         layout = wibox.layout.fixed.vertical,
      },
      margins = 14, widget = wibox.container.margin,
   }
   backdrop = popups.backdrop(function() cliphist.hide() end)
end

function cliphist.hide()
   if not open then return end
   open = false
   popup.visible = false
   backdrop.visible = false
   if grabber then awful.keygrabber.stop(grabber); grabber = nil end
end

function cliphist.show()
   if open then cliphist.hide(); return end
   popups.close_all("cliphist")
   target = client.focus
   load(function(ok)
      if not ok then
         naughty.notify({ title = "Clipboard history is not running",
            text = "CopyQ did not answer. It starts with the desktop; log out and in again, or run: copyq &" })
         return
      end
      if not popup then build() end
      if open then return end
      open = true
      sel, offset = 1, 0
      redraw()
      backdrop.show_on(awful.screen.focused())
      popup.visible = true
      grabber = awful.keygrabber.run(function(mods, key, event)
         if event ~= "press" then return end
         local shift = false
         for _, m in ipairs(mods) do if m == "Shift" then shift = true end end
         if key == "Escape" then cliphist.hide()
         elseif key == "Return" or key == "KP_Enter" then pick(sel)
         elseif key == "Delete" then forget(sel)
         elseif key == "Up" or ((key == "Tab" or key == "ISO_Left_Tab") and shift) then move(-1)
         elseif key == "Down" or key == "Tab" then move(1)
         elseif key == "Prior" then move(-MAX_ROWS)
         elseif key == "Next" then move(MAX_ROWS)
         elseif key == "Home" then move(-#items)
         elseif key == "End" then move(#items)
         end
      end)
   end)
end

popups.register("cliphist", cliphist.hide)

return cliphist
