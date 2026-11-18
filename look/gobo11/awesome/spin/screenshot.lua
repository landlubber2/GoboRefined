-- Screenshots (0.6). Win+Shift+S: a small card with Area / Window / Screen; Print: the whole
-- screen at once. The picture is saved as ~/Pictures/Screenshots/Screenshot_<date>_<time>.png,
-- put on the clipboard (as image/png), and announced by a notification; clicking the
-- notification opens the folder in the file manager.
--
-- 0.9.6: the screen is captured FIRST, as it is when the key is pressed, with any open menu or
-- popup on it (start menu, network list, desktop menu, Power card...), and only then are the
-- popups closed. Win+Shift+S shows that frozen picture over the whole screen and the card on top
-- of it; Area, Window and Screen are cut out of the frozen picture, so what was open stays in
-- the screenshot. (Before 0.9.6 the popup was closed first and the screen captured afterwards.)
--   Area:   drag a rectangle on the frozen picture (Escape or a right click cancels)
--   Window: the window that had the focus, as it was on the frozen picture (with its title bar;
--           whatever covered it then, e.g. an open menu, is in the picture too)
--   Screen: the monitor under the mouse pointer
-- Capturing uses ImageMagick's `import` on the root window (works with picom and with several
-- monitors) into ~/.cache/gobo-screenshot/frozen.png (the home folder is private); cutting and
-- saving is done with cairo.
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")
local beautiful = require("beautiful")
local cairo = require("lgi").cairo
local popups = require("spin.popups")

local screenshot = {}

local DIR = (os.getenv("HOME") or "/tmp") .. "/Pictures/Screenshots"
local CACHE = (os.getenv("HOME") or "/tmp") .. "/.cache/gobo-screenshot"
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

local function fail(text)
   naughty.notify({ preset = naughty.config.presets.critical, title = "Screenshot failed",
      text = (tostring(text or "")):gsub("%s+$", "") })
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

local frozen          -- cairo surface of the whole root window at the moment of the key press
local busy = false

-- capture the whole root window now; done(surface) or done(nil) on failure
function screenshot.freeze(done)
   local file = CACHE .. "/frozen.png"
   awful.spawn.easy_async({ "mkdir", "-p", "-m", "700", CACHE }, function()
      awful.spawn.easy_async({ "import", "-silent", "-window", "root", "png:" .. file },
         function(_, err, _, code)
            local surf = (code == 0) and gears.surface.load_uncached_silently(file, false) or nil
            os.remove(file)
            if not surf then fail(err ~= "" and err or "Could not capture the screen.") end
            done(surf)
         end)
   end)
end

-- geo: { x, y, width, height } in root window coordinates, cut out of the frozen picture
function screenshot.save(geo, done)
   if not frozen then return end
   geo.x, geo.y = math.floor(geo.x), math.floor(geo.y)
   geo.width, geo.height = math.floor(geo.width), math.floor(geo.height)
   if geo.width < 2 or geo.height < 2 then return end
   local file = DIR .. "/Screenshot_" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".png"
   local src = frozen
   awful.spawn.easy_async({ "mkdir", "-p", DIR }, function()
      local ok, err = pcall(function()
         local img = cairo.ImageSurface(cairo.Format.RGB24, geo.width, geo.height)
         local cr = cairo.Context(img)
         cr:set_source_surface(src, -geo.x, -geo.y)
         cr:paint()
         img:flush()
         local st = img:write_to_png(file)
         if st ~= nil and st ~= "SUCCESS" and st ~= 0 and st ~= true then error("cairo: " .. tostring(st)) end
      end)
      if not ok then fail(err) return end
      -- on the clipboard as a picture (xclip stays in the background to serve it)
      awful.spawn({ "xclip", "-selection", "clipboard", "-t", "image/png", "-i", file })
      notify_saved(file)
      if done then done(file) end
   end)
end
screenshot.capture = screenshot.save   -- old name (lab tests)

-- The frozen picture over every screen (while the card and the area selection are up) ----
local overlays = {}
local function hide_overlay()
   for _, o in ipairs(overlays) do o.visible = false end
   overlays = {}
end
local function show_overlay()
   hide_overlay()
   for s in screen do
      local g = s.geometry
      local o = wibox({ ontop = true, visible = false, type = "desktop", x = g.x, y = g.y,
         width = g.width, height = g.height, bg = "#000000" })
      local src = frozen
      o.bgimage = function(_, cr)
         cr:set_source_surface(src, -g.x, -g.y)
         cr:paint()
      end
      o.visible = true
      table.insert(overlays, o)
   end
end
screenshot.overlay_count = function() return #overlays end   -- lab tests

local function finish_all()
   hide_overlay()
   frozen = nil
   collectgarbage("step", 2000)
end

local function select_area(done)
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
      if geo then done(geo) else finish_all() end
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

-- cut `mode` out of the frozen picture and save it ("area", "window", "screen")
local function take_frozen(mode)
   local function save_and_finish(geo)
      screenshot.save(geo)
      finish_all()
   end
   if mode == "screen" then
      local g = (mouse.screen or awful.screen.focused()).geometry
      save_and_finish({ x = g.x, y = g.y, width = g.width, height = g.height })
   elseif mode == "window" then
      local c = client.focus
      if not (c and c.valid) then
         finish_all()
         naughty.notify({ title = "Screenshot", text = "No window had the focus: click a window first." })
         return
      end
      local g, bw = c:geometry(), c.border_width
      save_and_finish({ x = g.x, y = g.y, width = g.width + 2 * bw, height = g.height + 2 * bw })
   elseif mode == "area" then
      select_area(save_and_finish)
   else
      finish_all()
   end
end

-- capture first, then close every popup (and free the keyboard), then go on with the picture
local function capture_then(fn)
   if busy then return end
   busy = true
   screenshot.freeze(function(surf)
      busy = false
      popups.close_all()
      popups.release_grabs()
      if not surf then return end
      frozen = surf
      fn()
   end)
end

-- mode: "area", "window", "screen" (Print = "screen"): captured at once, popups included
function screenshot.take(mode)
   capture_then(function()
      if mode == "area" then show_overlay() end
      take_frozen(mode)
   end)
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

local function hide_card()
   if not open then return end
   open = false
   popup.visible = false
   backdrop.visible = false
   if grabber then awful.keygrabber.stop(grabber); grabber = nil end
end

local function choose(i)
   hide_card()
   take_frozen(ENTRIES[i][1])   -- the frozen picture stays up for the area selection
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
   backdrop = popups.backdrop(function() screenshot.hide() end, nil, function() return popup ~= nil and popup.visible end)
end

-- the card and the frozen picture go (Escape, a click beside the card, another popup)
function screenshot.hide()
   local was = open
   hide_card()
   if was then finish_all() end
end

function screenshot.is_open() return open end   -- lab tests

local function show_card()
   if not popup then build() end
   open = true
   sel = 1
   highlight()
   local s = awful.screen.focused()
   popup.x = s.geometry.x + math.floor((s.geometry.width - popup.width) / 2)
   popup.y = s.geometry.y + math.floor((s.geometry.height - popup.height) / 2)
   show_overlay()           -- the frozen picture first, then the sheet and the card above it
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

-- Win+Shift+S: capture now (with whatever is open), close the popups, then the card over the
-- frozen picture. Pressed again while the card is up: the card closes.
function screenshot.show()
   if open then screenshot.hide(); return end
   capture_then(show_card)
end

popups.register("screenshot", screenshot.hide)

return screenshot
