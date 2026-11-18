-- 0.9.6: "Frequently used apps" next to the start menu (the dots menu).
--
-- The last entry of the start menu, "<- Frequently used apps", opens a panel on the LEFT of the
-- menu, as high as the menu (so the whole thing is about twice as wide); the entry then reads
-- "Hide frequently used apps". The choice is remembered per user and the panel comes back with
-- every opening of the menu until it is hidden again.
--
-- The panel has a fixed number of slots (SLOTS = 8: the full start menu is 12 rows of 34 px,
-- which leaves room for a heading and 8 rows of 44 px, the same row count as the search).
-- Pinned items fill the slots first, in the order they were pinned; the remaining slots show the
-- most used apps that are not pinned. With 8 pins there are no "most used" apps any more.
--
-- Files (per user, in ~/.config/goborefined/, which the look's apply.sh never touches, so they
-- survive system updates and rollbacks):
--   start-frequent  "shown" while the panel is switched on
--   start-pins      one pin per line: "app<TAB>desktop-id" | "file<TAB>/path" | "folder<TAB>/path"
--   app-usage       "count<TAB>last-start (epoch)<TAB>desktop-id", counted for apps started from the
--                   start menu, the search and this panel. Ageing: when the counts add up to more
--                   than 100, every count is halved (rounded down) and apps that reach 0 are
--                   dropped (not the app just started), so an old favourite that is no longer started fades out. At most 60
--                   lines are kept.
-- Pinning: right click on an app in the start menu, the search or the panel ("Pin to start" /
-- "Unpin"); files and folders from the file manager (PCManFM action "Pin to start", which runs
-- gobo-pin-to-start; it calls spin_start_pins_reload()). A pin whose target is gone is shown
-- greyed and can be unpinned.
-- Speed: the app list comes from the start menu's own scan (menu_gen, once at start); opening the
-- menu reads two small files only when they changed (modification time) and checks whether the
-- (at most 8) pinned files still exist. No folder is scanned.
-- Simple accounts: the panel works with their own programs; files and folders cannot be pinned.
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local menubar = require("menubar")
local Gio = require("lgi").Gio
local ctxmenu = require("spin.ctxmenu")

local M = {}
M.SLOTS = 8
local HEADER_H = 44
local MAX_USAGE, AGE_AT = 60, 100

local home = os.getenv("HOME") or ""
M.dir = home .. "/.config/goborefined"
M.shown_file = M.dir .. "/start-frequent"
M.pins_file = M.dir .. "/start-pins"
M.usage_file = M.dir .. "/app-usage"
M.file_manager = "pcmanfm"
M.allow_files = true      -- false for Simple accounts (rc.lua)

-- Desktop-file ids ----------------------------------------------------------------------
-- menu_gen (Awesome 4.3) does not hand out the desktop file of an entry. Every file it reads
-- passes through menubar.utils.parse_desktop_file: remember "Name\0cmdline" -> file name there.
local id_of = {}
do
   local utils = menubar.utils
   local parse = utils.parse_desktop_file
   utils.parse_desktop_file = function(file)
      local p = parse(file)
      if p and p.Name and p.cmdline and type(file) == "string" then
         id_of[(utils.rtrim(p.Name) or "") .. "\0" .. (utils.rtrim(p.cmdline) or "")] = file:match("([^/]+%.desktop)$")
      end
      return p
   end
end

function M.id_for(name, cmdline)
   return id_of[(name or "") .. "\0" .. (cmdline or "")]
end

local apps = {}           -- id -> { id, name, cmdline, icon }
-- the start menu's list (rc.lua, after menu_gen; only the programs the account may run)
function M.set_apps(entries)
   local list = {}
   for _, e in ipairs(entries) do
      local id = e.id or M.id_for(e.name, e.cmdline)
      if id and not list[id] then
         list[id] = { id = id, name = e.name, cmdline = e.cmdline, icon = e.icon }
      end
   end
   apps = list
   M.refresh()
end
function M.app(id) return apps[id] end

-- small files --------------------------------------------------------------------------
local function mtime(path)
   local ok, info = pcall(function()
      return Gio.File.new_for_path(path):query_info("time::modified", Gio.FileQueryInfoFlags.NONE, nil)
   end)
   if not ok or not info then return 0 end
   return info:get_attribute_uint64("time::modified") or 0
end

local function lines(path)
   local list = {}
   local f = io.open(path, "r")
   if not f then return list end
   for line in f:lines() do
      if line ~= "" and not line:match("^#") then table.insert(list, line) end
   end
   f:close()
   return list
end

local function write(path, text)
   os.execute("mkdir -p '" .. M.dir:gsub("'", "'\\''") .. "'")
   local tmp = path .. ".new"
   local f = io.open(tmp, "w")
   if not f then return false end
   f:write(text)
   f:close()
   return os.rename(tmp, path)
end

local pins, pins_mtime = {}, -1          -- { { kind = "app"|"file"|"folder", target = ... } }
local usage, usage_mtime = {}, -1        -- id -> { count, last }

local function load_pins(force)
   local t = mtime(M.pins_file)
   if not force and t == pins_mtime then return end
   pins_mtime = t
   pins = {}
   local seen = {}
   for _, line in ipairs(lines(M.pins_file)) do
      local kind, target = line:match("^(%a+)\t(.+)$")
      if (kind == "app" or kind == "file" or kind == "folder") and not seen[kind .. target] then
         seen[kind .. target] = true
         table.insert(pins, { kind = kind, target = target })
      end
   end
end

local function save_pins()
   local out = { "# GoboRefined start menu pins (kind<TAB>target), in pin order\n" }
   for _, p in ipairs(pins) do table.insert(out, p.kind .. "\t" .. p.target .. "\n") end
   write(M.pins_file, table.concat(out))
   pins_mtime = mtime(M.pins_file)
end

local function load_usage(force)
   local t = mtime(M.usage_file)
   if not force and t == usage_mtime then return end
   usage_mtime = t
   usage = {}
   for _, line in ipairs(lines(M.usage_file)) do
      local c, last, id = line:match("^(%d+)\t(%d+)\t(%S+)$")
      if id then usage[id] = { count = tonumber(c), last = tonumber(last) } end
   end
end

local function sorted_usage()
   local list = {}
   for id, u in pairs(usage) do table.insert(list, { id = id, count = u.count, last = u.last }) end
   table.sort(list, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      if a.last ~= b.last then return a.last > b.last end
      return a.id < b.id
   end)
   return list
end

local function save_usage()
   local out = { "# GoboRefined app starts (count<TAB>last start<TAB>desktop id); halved when the sum passes 100\n" }
   for i, u in ipairs(sorted_usage()) do
      if i > MAX_USAGE then break end
      table.insert(out, string.format("%d\t%d\t%s\n", u.count, u.last, u.id))
   end
   write(M.usage_file, table.concat(out))
   usage_mtime = mtime(M.usage_file)
end

-- one more start of the app `id`
function M.count(id)
   if not id or not id:match("^[%w][%w._+@-]*%.desktop$") then return end
   load_usage()
   local u = usage[id] or { count = 0, last = 0 }
   u.count, u.last = u.count + 1, os.time()
   usage[id] = u
   local sum = 0
   for _, v in pairs(usage) do sum = sum + v.count end
   if sum > AGE_AT then
      for k, v in pairs(usage) do
         v.count = math.floor(v.count / 2)
         if v.count == 0 and k ~= id then usage[k] = nil end
      end
      u.count = math.max(u.count, 1)   -- the app just started stays in the list

   end
   save_usage()
end

-- start an app through the panel's counting (start menu, search, panel)
function M.launch(app)
   if type(app) == "string" then app = apps[app] end
   if not app then return end
   awful.spawn(app.cmdline)
   M.count(app.id or M.id_for(app.name, app.cmdline))
end

-- pins ------------------------------------------------------------------------------------
function M.pinned(kind, target)
   load_pins()
   for i, p in ipairs(pins) do
      if p.kind == kind and p.target == target then return i end
   end
end

local function note(text)
   naughty.notify({ title = "Start menu", text = text, timeout = 4 })
end

function M.pin(kind, target)
   if not target or target:find("[\t\n]") then return false end
   if kind ~= "app" and not M.allow_files then note("This account can pin programs only.") return false end
   load_pins()
   if M.pinned(kind, target) then return true end
   if #pins >= M.SLOTS then
      note(string.format("All %d places are pinned. Unpin something first.", M.SLOTS))
      return false
   end
   table.insert(pins, { kind = kind, target = target })
   save_pins()
   M.refresh()
   return true
end

function M.unpin(kind, target)
   local i = M.pinned(kind, target)
   if i then
      table.remove(pins, i)
      save_pins()
      M.refresh()
   end
end

-- called by gobo-pin-to-start (file manager action) through awesome-client
function spin_start_pins_reload()
   load_pins(true)
   M.refresh()
   return #pins
end

-- right click on an app (start menu, search, panel)
function M.app_context(app)
   local id = app and (app.id or M.id_for(app.name, app.cmdline))
   if not id then return end
   if M.pinned("app", id) then
      ctxmenu.show({ { "Unpin from start", function() M.unpin("app", id) end } })
   else
      ctxmenu.show({ { "Pin to start", function() M.pin("app", id) end } })
   end
end

-- the slots: pins first, then the most used apps that are not pinned -----------------------
local function exists(kind, target)
   if kind == "folder" then return gears.filesystem.dir_readable(target) end
   return gears.filesystem.file_readable(target) or gears.filesystem.dir_readable(target)
end

-- icons by name at row size (menubar.utils.lookup_icon finds only application-sized icons)
local function find_icon(name)
   local ok, path = pcall(function() return require("menubar.icon_theme")():find_icon_path(name, 24) end)
   return (ok and path) or menubar.utils.lookup_icon(name)
end
local file_icons = {}
local function file_icon(kind, path)
   if kind == "folder" then
      return find_icon("folder") or beautiful.default_app_icon
   end
   if file_icons[path] == nil then
      local icon
      pcall(function()
         local ctype = Gio.content_type_guess(path, nil)
         local gicon = ctype and Gio.content_type_get_icon(ctype)
         for _, n in ipairs(gicon and gicon:get_names() or {}) do
            icon = find_icon(n)
            if icon then break end
         end
      end)
      file_icons[path] = icon or find_icon("text-x-generic") or beautiful.default_app_icon
   end
   return file_icons[path]
end

function M.slots()
   load_pins()
   load_usage()
   local list, taken = {}, {}
   for _, p in ipairs(pins) do
      if #list >= M.SLOTS then break end
      local s = { kind = p.kind, target = p.target, pinned = true }
      if p.kind == "app" then
         local a = apps[p.target]
         s.app, s.missing = a, a == nil
         s.name = a and a.name or p.target:gsub("%.desktop$", "")
         s.icon = a and a.icon or beautiful.default_app_icon
         taken[p.target] = true
      else
         s.missing = not exists(p.kind, p.target)
         s.name = p.target:match("([^/]+)/*$") or p.target
         s.icon = file_icon(p.kind, p.target)
      end
      table.insert(list, s)
   end
   for _, u in ipairs(sorted_usage()) do
      if #list >= M.SLOTS then break end
      local a = apps[u.id]
      if a and not taken[u.id] then
         table.insert(list, { kind = "app", target = u.id, app = a, name = a.name, icon = a.icon or beautiful.default_app_icon })
      end
   end
   return list
end

-- the panel --------------------------------------------------------------------------------
local panel, menu_ref, rows_box
local visible = false

function M.enabled()
   local f = io.open(M.shown_file, "r")
   if not f then return false end
   local v = f:read("*l")
   f:close()
   return v == "shown"
end

function M.toggle_label()
   return M.enabled() and "Hide frequently used apps" or "\u{2190} Frequently used apps"
end

local function open_slot(s)
   if s.missing then
      note((s.kind == "app" and "This program is no longer installed: " or "Not found: ") .. s.target
         .. "\nRight-click it to unpin it.")
      return
   end
   if menu_ref then menu_ref:hide() end
   if s.kind == "app" then
      M.launch(s.app)
   elseif s.kind == "folder" then
      awful.spawn({ M.file_manager, s.target })
   else
      awful.spawn({ "xdg-open", s.target })
   end
end

local function slot_context(s)
   if s.pinned then
      ctxmenu.show({ { "Unpin", function() M.unpin(s.kind, s.target) end } })
   else
      ctxmenu.show({ { "Pin to start", function() M.pin("app", s.target) end } })
   end
end

local function dim(text)
   return '<span foreground="' .. beautiful.palette.fg_dim .. '">' .. gears.string.xml_escape(text) .. '</span>'
end

local function build_rows(height)
   rows_box:reset()
   local row_h = math.max(28, math.floor((height - HEADER_H - 8) / M.SLOTS))
   local list = M.slots()
   for i = 1, M.SLOTS do
      local s = list[i]
      local row
      if s then
         local icon = wibox.widget { image = s.icon, forced_width = 24, forced_height = 24, widget = wibox.widget.imagebox }
         local name = wibox.widget { text = s.name, font = beautiful.font, ellipsize = "end", widget = wibox.widget.textbox }
         local tag = wibox.widget { markup = s.missing and dim("not found") or (s.pinned and dim("pinned") or ""),
            font = beautiful.font_small, widget = wibox.widget.textbox }
         row = wibox.widget {
            { { { icon, valign = "center", widget = wibox.container.place },
                { name, left = 12, right = 8, widget = wibox.container.margin },
                tag, layout = wibox.layout.align.horizontal },
              left = 12, right = 12, widget = wibox.container.margin },
            forced_height = row_h, shape = beautiful.button_shape,
            opacity = s.missing and 0.45 or 1,
            widget = wibox.container.background,
         }
         row:connect_signal("mouse::enter", function() row.bg = beautiful.hover_bg end)
         row:connect_signal("mouse::leave", function() row.bg = nil end)
         row:buttons(gears.table.join(
            awful.button({}, 1, nil, function() ctxmenu.hide(); open_slot(s) end),
            awful.button({}, 3, nil, function() slot_context(s) end)))
      else
         local hint = (i == 1) and "Apps you start often appear here." or
                      (i == 2 and #list == 0) and "Right-click an app to pin it." or ""
         row = wibox.widget {
            { markup = dim(hint), font = beautiful.font_small, widget = wibox.widget.textbox },
            left = 16, forced_height = row_h, widget = wibox.container.margin,
         }
      end
      rows_box:add(row)
   end
end

local function build()
   rows_box = wibox.layout.fixed.vertical()
   rows_box.spacing = 0
   panel = wibox({ ontop = true, visible = false, type = "popup_menu",
      bg = beautiful.menu_bg_normal, fg = beautiful.fg_normal,
      border_width = 1, border_color = beautiful.menu_border_color,
      shape = beautiful.menu_shape })
   panel:setup {
      {
         { { markup = "<b>Pinned and frequent</b>", font = beautiful.font, forced_height = HEADER_H - 8,
             widget = wibox.widget.textbox },
           left = 16, top = 4, widget = wibox.container.margin },
         { rows_box, left = 4, right = 4, bottom = 4, widget = wibox.container.margin },
         layout = wibox.layout.fixed.vertical,
      },
      bg = beautiful.menu_bg_normal,   -- as opaque as the menu (its rows have a background of their own)
      widget = wibox.container.background,
   }
   spin_debug = spin_debug or {}
   spin_debug.startpanel = panel   -- lab tests
end

function M.hide()
   ctxmenu.hide()
   if panel then panel.visible = false end
   visible = false
end

function M.is_visible() return visible end

-- place the panel left of the menu `m` (an awful.menu that is on screen); if there is no room on
-- the left (taskbar aligned left), the menu moves right by the panel's width
function M.show_for(m)
   menu_ref = m
   if not M.enabled() or not (m and m.wibox and m.wibox.visible) then M.hide() return end
   if not panel then build() end
   local mw = m.wibox
   local width = mw.width
   local g = (awful.screen.focused() or screen.primary).geometry
   local x = mw.x - width - 2
   if x < g.x then
      mw.x = math.min(g.x + width + 2, g.x + g.width - mw.width)
      m.x = mw.x
      x = mw.x - width - 2
   end
   local height = mw.height + 2 * (mw.border_width or 0) - 2
   build_rows(height)
   panel:geometry({ x = math.max(g.x, x), y = mw.y, width = width, height = height })
   panel.visible = true   -- after the menu: stacked above its click sheet
   visible = true
end

function M.refresh()
   if visible and menu_ref then M.show_for(menu_ref) end
end

function M.set_enabled(on)
   if on then write(M.shown_file, "shown\n") else os.remove(M.shown_file) end
end

-- the start menu's last entry: switch the panel on or off, the menu stays open
function M.toggle(m, item)
   M.set_enabled(not M.enabled())
   if item and item.label then item.label:set_text(M.toggle_label()) end
   if M.enabled() then M.show_for(m) else M.hide() end
end

return M
