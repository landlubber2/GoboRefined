-- GoboRefined Settings (gobo-settings): one window. 0.9.2: the first view is an overview of
-- categories with a tile per page (like a phone's settings); a tile opens its page, "All settings"
-- (or Escape) goes back. Lua + lgi + GTK 3 (all on the image: Awesome uses lgi).
-- Colours and font follow the GTK theme (light/dark from ~/.config/gtk-3.0/settings.ini, Inter).
--
-- HOW TO ADD A PAGE: write pages/<id>.lua returning
--    { id = "<id>", title = "Title", icon = "<icon name>", build = function(C) return widget end }
-- (build runs the first time the page is shown; C = common.lua: dialogs, commands, the root
-- helper), add "<id>" to PAGES and to one category in CATEGORIES below. Anything that needs root becomes a new, strictly
-- checked sub-command of gobo-settings-helper, called with C.helper({...}).
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-settings")   -- window class (the taskbar icon, lab tests)
lgi.GLib.set_application_name("Settings")
local Gtk = lgi.require("Gtk", "3.0")
local Gdk = lgi.require("Gdk", "3.0")
local C = require("common")

local PAGES = {
   "network", "bluetooth", "hotspot", "remote",
   "appearance", "trash",
   "displays", "sound", "devices",
   "updates", "apps",
   "accounts", "about",
}
-- 0.9.2: the overview. A category is shown when at least one of its pages is.
local CATEGORIES = {
   { title = "Connectivity", pages = { "network", "bluetooth", "hotspot", "remote" } },
   { title = "Customization", pages = { "appearance", "trash" } },
   { title = "Devices", pages = { "displays", "sound", "devices" } },
   { title = "Software", pages = { "updates", "apps" } },
   { title = "Accounts and system", pages = { "accounts", "about" } },
}
local TILE_TITLE = { remote = "Remote access (SSH)" }   -- tile label when it differs from the page title
local CATEGORY_OF = {}
for _, cat in ipairs(CATEGORIES) do for _, id in ipairs(cat.pages) do CATEGORY_OF[id] = cat.title end end
-- 0.9.1: what each kind of account sees (the helper refuses system changes to non-administrators
-- in any case; this keeps pages they cannot use out of their way). Accounts = own password.
local KIND_PAGES = {
   simple   = { appearance = true, accounts = true, sound = true, about = true },
   standard = { appearance = true, accounts = true, sound = true, about = true,
                network = true, bluetooth = true, displays = true, trash = true,
                devices = true, apps = true },   -- 0.9.2: both read-only for them
}
do
   local allowed = KIND_PAGES[C.kind()]
   if allowed then
      local kept = {}
      for _, id in ipairs(PAGES) do if allowed[id] then table.insert(kept, id) end end
      PAGES = kept
   end
end

local css = Gtk.CssProvider()
css:load_from_data([[
.gobo-tile { border-radius: 10px; padding: 8px; }
.gobo-topbar { padding: 4px 10px; }
.gobo-title { font-size: 20pt; font-weight: 600; }
.gobo-heading { font-size: 12pt; font-weight: 600; }
.gobo-value { font-weight: 600; }
]])
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

local window = Gtk.Window { title = "Settings", default_width = 980, default_height = 660, icon_name = "preferences-system" }
window.on_destroy = Gtk.main_quit
C.window = window

local stack = Gtk.Stack { transition_type = Gtk.StackTransitionType.CROSSFADE, transition_duration = 120 }
local pages, built = {}, {}   -- pages[id] = page table
for _, id in ipairs(PAGES) do
   local ok, page = pcall(require, "pages." .. id)
   if ok and type(page) == "table" then
      pages[id] = page
   else
      io.stderr:write("gobo-settings: page " .. id .. ": " .. tostring(page) .. "\n")
   end
end

-- the bar on top of a page: back to the overview
local back = Gtk.Button { relief = Gtk.ReliefStyle.NONE, halign = Gtk.Align.START }
do
   local b = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
   b:pack_start(Gtk.Image { icon_name = "go-previous-symbolic", pixel_size = 16 }, false, false, 0)
   b:pack_start(Gtk.Label { label = "All settings" }, false, false, 0)
   back:add(b)
end
local crumb = Gtk.Label { xalign = 0 }
crumb:get_style_context():add_class("dim-label")
local topbar = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 10 }
topbar:get_style_context():add_class("gobo-topbar")
topbar:pack_start(back, false, false, 0)
topbar:pack_start(crumb, false, false, 0)
local topbar_revealer = Gtk.Revealer { transition_type = Gtk.RevealerTransitionType.NONE, reveal_child = false }
local topbox = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
topbox:pack_start(topbar, false, false, 0)
topbox:pack_start(Gtk.Separator { orientation = Gtk.Orientation.HORIZONTAL }, false, false, 0)
topbar_revealer:add(topbox)

local current = "home"
local function show_home()
   current = "home"
   stack:set_visible_child_name("home")
   topbar_revealer.reveal_child = false
   window.title = "Settings"
end
local function select_page(id)
   local page = pages[id]
   if not page then return false end
   if not built[id] then
      local ok, w = pcall(page.build, C)
      if not ok then w = C.text("This page could not be built:\n" .. tostring(w)) end
      stack:add_named(w, id)
      w:show_all()
      built[id] = true
   end
   current = id
   stack:set_visible_child_name(id)
   crumb.label = (CATEGORY_OF[id] or "") .. "  ›  " .. page.title
   topbar_revealer.reveal_child = true
   window.title = page.title .. " - Settings"
   return true
end
back.on_clicked = show_home

-- the overview: categories, each with tiles
local home = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6, margin = 28 }
do
   local t = Gtk.Label { label = "Settings", xalign = 0 }
   t:get_style_context():add_class("gobo-title")
   home:pack_start(t, false, false, 0)
end
local first_tile
for _, cat in ipairs(CATEGORIES) do
   local flow = Gtk.FlowBox { selection_mode = Gtk.SelectionMode.NONE, homogeneous = true, max_children_per_line = 6,
                              min_children_per_line = 2, column_spacing = 10, row_spacing = 10, halign = Gtk.Align.START }
   local n = 0
   for _, id in ipairs(cat.pages) do
      local page = pages[id]
      if page then
         n = n + 1
         local tile = Gtk.Button { width_request = 176, height_request = 104 }
         tile:get_style_context():add_class("gobo-tile")
         local b = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 8, valign = Gtk.Align.CENTER }
         b:pack_start(Gtk.Image { icon_name = page.icon, pixel_size = 36 }, false, false, 0)
         b:pack_start(Gtk.Label { label = TILE_TITLE[id] or page.title, wrap = true, justify = Gtk.Justification.CENTER, max_width_chars = 16 }, false, false, 0)
         tile:add(b)
         tile.on_clicked = function() select_page(id) end
         flow:add(tile)
         first_tile = first_tile or tile
      end
   end
   if n > 0 then
      local h = C.heading(cat.title)
      h.margin_top = 18
      home:pack_start(h, false, false, 0)
      home:pack_start(flow, false, false, 0)
   end
end
local home_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER }
home_scroll:add(home)
stack:add_named(home_scroll, "home")

local root = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
root:pack_start(topbar_revealer, false, false, 0)
root:pack_start(stack, true, true, 0)
window:add(root)

-- Escape: back to the overview, and from there it closes the window; Alt+Left goes back too
window.on_key_press_event = function(_, event)
   if event.keyval == Gdk.KEY_Escape then
      if current == "home" then window:destroy() else show_home() end
      return true
   elseif event.keyval == Gdk.KEY_Left and event.state.MOD1_MASK and current ~= "home" then
      show_home()
      return true
   end
   return false
end

window:show_all()
show_home()
if first_tile then first_tile:grab_focus() end
if arg[1] and arg[1] ~= "" then select_page(arg[1]) end

-- 0.8.2: a second "gobo-settings PAGE" raises this window (the launcher asks the desktop) and
-- writes PAGE into this file; switch to it ("home" = the overview)
local page_file = C.HOME .. "/.cache/gobo-settings.page"
os.remove(page_file)
local page_monitor = C.Gio.File.new_for_path(page_file):monitor_file(C.Gio.FileMonitorFlags.NONE, nil)
if page_monitor then
   page_monitor.on_changed = function(_, _, _, event)
      if event ~= "CHANGES_DONE_HINT" and event ~= "CREATED" then return end
      local id = C.trim(C.read(page_file) or "")
      if id ~= "" then
         os.remove(page_file)
         if id == "home" then show_home() else select_page(id) end
         window:present()
      end
   end
end
Gtk.main()
