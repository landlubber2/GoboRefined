-- Screenshots (0.6). Win+Shift+S: a small card with Area / Window / Screen; Print: the whole
-- screen at once. The picture is saved as ~/Pictures/Screenshots/Screenshot_<date>_<time>.png,
-- put on the clipboard (as image/png), and announced by a notification; clicking the
-- notification opens the folder in the file manager.
-- Capturing uses ImageMagick's `import` (on the 017.01 image) on the root window, cropped to
-- the chosen rectangle, so it works with picom running and with several monitors.
--   Area:   drag a rectangle with the mouse (Escape or a right click cancels)
--   Window: the window that had the focus (with its title bar)
--   Screen: the monitor under the mouse pointer
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local beautiful = require("beautiful")
local cairo = require("lgi").cairo
local popups = require("spin.popups")

local screenshot = {}

local DIR = (os.getenv("HOME") or "/tmp") .. "/Pictures/Screenshots"
screenshot.file_manager = "pcmanfm"

-- Icons for the card -------------------------------------------------------------------
local function glyph(draw)
   local img = cairo.ImageSurface("ARGB32", 48, 48)
   local cr = cairo.Context(img)
   local r, g, b = gears.color.parse_color(beautiful.fg_normal)
   cr:set_source_rgba(r, g, b, 1)
   cr:set_line_width(3)
   cr:set_line_cap(cairo.LineCap.ROUND)
   cr:set_line_join(cairo.LineJoin.ROUND)
   draw(cr)
   return img
end
local function icons()
   return {
      area = glyph(function(cr)   -- four corner marks and a small cross
         for _, c in ipairs({ { 8, 10, 1, 1 }, { 40, 10, -1, 1 }, { 8, 38, 1, -1 }, { 40, 38, -1, -1 } }) do
            cr:move_to(c[1], c[2] + 7 * c[4]); cr:line_to(c[1], c[2]); cr:line_to(c[1] + 7 * c[3], c[2])
         end
         cr:stroke()
         cr:move_to(24, 19); cr:line_to(24, 29); cr:move_to(19, 24); cr:line_to(29, 24); cr:stroke()
      end),
      window = glyph(function(cr)
         cr:translate(7, 9); gears.shape.rounded_rect(cr, 34, 30, 3); cr:stroke()
         cr:move_to(0, 9); cr:line_to(34, 9); cr:stroke()
      end),
      screen = glyph(function(cr)
         cr:translate(5, 8); gears.shape.rounded_rect(cr, 38, 25, 3); cr:stroke()
         cr:move_to(12, 33); cr:line_to(26, 33); cr:move_to(19, 26); cr:line_to(19, 33); cr:stroke()
      end),
   }
end

-- Capture ----------------------------------------------------------------------------
local function notify_saved(file)
   local folder = DIR
   local n
   n = naughty.notify({
      title = "Screenshot saved",
      text = file:match("[^/]+$") .. "\nIn Pictures/Screenshots and on the clipboard. Click to open the folder.",
      icon = file, icon_size = 64, timeout = 8,
      run = function(notification)
         awful.spawn({ screenshot.file_manager, folder })
         naughty.destroy(notification)
      end,
   })
   return n
end

-- geo: { x, y, width, height } in root window coordinates
function screenshot.capture(geo, done)
   geo.width, geo.height = math.floor(geo.width), math.floor(geo.height)
   if geo.width < 2 or geo.height < 2 then return end
   local file = DIR .. "/Screenshot_" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".png"
   local crop = string.format("%dx%d+%d+%d", geo.width, geo.height, math.floor(geo.x), math.floor(geo.y))
   awful.spawn.easy_async({ "mkdir", "-p", DIR }, function()
      awful.spawn.easy_async({ "import", "-silent", "-window", "root", "-crop", crop, "+repage", file },
         function(_, err, _, code)
            if code ~= 0 then
               naughty.notify({ preset = naughty.config.presets.critical, title = "Screenshot failed",
                  text = (err or ""):gsub("%s+$", "") })
               return
            end
            -- on the clipboard as a picture (xclip stays in the background to serve it)
            awful.spawn({ "xclip", "-selection", "clipboard", "-t", "image/png", "-i", file })
            notify_saved(file)
            if done then done(file) end
         end)
   end)
end

-- picom fades popups out: wait until they are gone from the screen
local function later(fn) gears.timer.start_new(0.35, function() fn(); return false end) end

local function select_area(done)
   local s = awful.screen.focused()
   -- a dark veil over every screen; the selected rectangle is drawn as a frame
   local veils = {}
   for sc in screen do
      local v = wibox({ ontop = true, visible = true, bg = "#00000040", type = "utility",
         x = sc.geometry.x, y = sc.geometry.y, width = sc.geometry.width, height = sc.geometry.height })
      v.cursor = "crosshair"
      table.insert(veils, v)
   end
   local frame = wibox({ ontop = true, visible = false, bg = "#00000000", type = "utility",
      border_width = 2, border_color = beautiful.accent or "#4cc2ff" })
   local start, grabber
   local function finish(geo)
      if grabber then awful.keygrabber.stop(grabber); grabber = nil end
      if mousegrabber.isrunning() then mousegrabber.stop() end
      for _, v in ipairs(veils) do v.visible = false end
      frame.visible = false
      popups.register("screenshot-area", nil)
      if geo then later(function() done(geo) end) end
   end
   popups.register("screenshot-area", function() finish(nil) end)
   grabber = awful.keygrabber.run(function(_, key, event)
      if event == "press" and key == "Escape" then finish(nil) end
   end)
   mousegrabber.run(function(m)
      if m.buttons[3] then finish(nil); return false end
      if not start then
         if m.buttons[1] then start = { x = m.x, y = m.y } end
         return true
      end
      local x, y = math.min(start.x, m.x), math.min(start.y, m.y)
      local w, h = math.abs(m.x - start.x), math.abs(m.y - start.y)
      if w > 2 and h > 2 then
         frame:geometry({ x = x - 2, y = y - 2, width = w, height = h })
         frame.visible = true
      end
      if not m.buttons[1] then
         finish({ x = x, y = y, width = w, height = h })
         return false
      end
      return true
   end, "crosshair")
end

-- mode: "area", "window", "screen"
function screenshot.take(mode)
   if mode == "screen" then
      local g = awful.screen.focused().geometry
      later(function() screenshot.capture({ x = g.x, y = g.y, width = g.width, height = g.height }) end)
   elseif mode == "window" then
      local c = client.focus
      if not c then
         naughty.notify({ title = "Screenshot", text = "No window has the focus: click a window first." })
         return
      end
      c:raise()
      later(function()
         if not c.valid then return end
         local g, bw = c:geometry(), c.border_width
         screenshot.capture({ x = g.x, y = g.y, width = g.width + 2 * bw, height = g.height + 2 * bw })
      end)
   elseif mode == "area" then
      select_area(function(geo) screenshot.capture(geo) end)
   end
end

-- The card ---------------------------------------------------------------------------
local popup, backdrop, buttons, grabber
local sel = 1
local open = false
local ENTRIES = {
   { "area", "Area", "a" }, { "window", "Window", "w" }, { "screen", "Whole screen", "s" },
}

local function highlight()
   for i, b in ipairs(buttons) do b.bg = (i == sel) and beautiful.active_bg or nil end
end

local function choose(i)
   screenshot.hide()
   screenshot.take(ENTRIES[i][1])
end

local function build()
   local ic = icons()
   buttons = {}
   local row = wibox.layout.fixed.horizontal()
   row.spacing = 8
   for i, e in ipairs(ENTRIES) do
      local b = wibox.widget {
         {
            {
               { { image = ic[e[1]], forced_width = 30, forced_height = 30, widget = wibox.widget.imagebox },
                 halign = "center", widget = wibox.container.place },
               { text = e[2], align = "center", font = beautiful.font_small, widget = wibox.widget.textbox },
               spacing = 10, layout = wibox.layout.fixed.vertical,
            },
            left = 8, right = 8, top = 14, bottom = 12, widget = wibox.container.margin,
         },
         forced_width = 104, shape = beautiful.button_shape, widget = wibox.container.background,
      }
      b:connect_signal("mouse::enter", function() sel = i; highlight() end)
      b:buttons(awful.button({}, 1, nil, function() choose(i) end))
      buttons[i] = b
      row:add(b)
   end
   popup = wibox({
      width = 3 * 104 + 2 * 8 + 28, height = 118 + 26, ontop = true, visible = false,
      bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
      border_width = 1, border_color = beautiful.menu_border_color,
      shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 10) end,
      type = "popup_menu",
   })
   popup:setup {
      { row,
        { markup = '<span foreground="' .. beautiful.palette.fg_dim .. '">Saved to Pictures/Screenshots and copied</span>',
          font = beautiful.font_small, align = "center", widget = wibox.widget.textbox },
        spacing = 6, layout = wibox.layout.fixed.vertical },
      margins = 14, widget = wibox.container.margin,
   }
   backdrop = popups.backdrop(function() screenshot.hide() end)
end

function screenshot.hide()
   if not open then return end
   open = false
   popup.visible = false
   backdrop.visible = false
   if grabber then awful.keygrabber.stop(grabber); grabber = nil end
end

function screenshot.show()
   if not popup then build() end
   if open then screenshot.hide(); return end
   popups.close_all("screenshot")
   open = true
   sel = 1
   highlight()
   local s = awful.screen.focused()
   popup.x = s.geometry.x + math.floor((s.geometry.width - popup.width) / 2)
   popup.y = s.geometry.y + math.floor((s.geometry.height - popup.height) / 2)
   backdrop.show_on(s)
   popup.visible = true
   grabber = awful.keygrabber.run(function(mods, key, event)
      if event ~= "press" then return end
      local shift = false
      for _, m in ipairs(mods) do if m == "Shift" then shift = true end end
      if key == "Escape" then screenshot.hide()
      elseif key == "Return" or key == "KP_Enter" or key == "space" then choose(sel)
      elseif key == "Left" or key == "Up" or ((key == "Tab" or key == "ISO_Left_Tab") and shift) then
         sel = (sel - 2) % #ENTRIES + 1; highlight()
      elseif key == "Right" or key == "Down" or key == "Tab" then
         sel = sel % #ENTRIES + 1; highlight()
      else
         for i, e in ipairs(ENTRIES) do if key:lower() == e[3] then choose(i) return end end
      end
   end)
end

popups.register("screenshot", screenshot.hide)

return screenshot
