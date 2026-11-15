-- GoboRefined Settings (gobo-settings), 0.8.2: one window, pages in a sidebar on the left,
-- the chosen page on the right. Lua + lgi + GTK 3 (all on the image: Awesome uses lgi).
-- Colours and font follow the GTK theme (light/dark from ~/.config/gtk-3.0/settings.ini, Inter).
--
-- HOW TO ADD A PAGE: write pages/<id>.lua returning
--    { id = "<id>", title = "Title", icon = "<icon name>", build = function(C) return widget end }
-- (build runs the first time the page is shown; C = common.lua: dialogs, commands, the root
-- helper) and add "<id>" to PAGES below. Anything that needs root becomes a new, strictly
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
   "appearance", "accounts", "updates", "remote", "network",
   "bluetooth", "hotspot",   -- 0.8.2 part 2, experimental
   "sound", "displays", "trash", "about",
}

local css = Gtk.CssProvider()
css:load_from_data([[
.gobo-sidebar { padding: 8px 6px; }
.gobo-sidebar row { padding: 9px 12px; border-radius: 6px; margin: 1px 4px; }
.gobo-title { font-size: 20pt; font-weight: 600; }
.gobo-heading { font-size: 12pt; font-weight: 600; }
.gobo-value { font-weight: 600; }
]])
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

local window = Gtk.Window { title = "Settings", default_width = 960, default_height = 640, icon_name = "preferences-system" }
window.on_destroy = Gtk.main_quit
C.window = window

local sidebar = Gtk.ListBox { selection_mode = Gtk.SelectionMode.BROWSE }
sidebar:get_style_context():add_class("gobo-sidebar")
local side_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER, width_request = 220 }
side_scroll:add(sidebar)
local stack = Gtk.Stack { transition_type = Gtk.StackTransitionType.CROSSFADE, transition_duration = 120 }

local pages, built = {}, {}
for _, id in ipairs(PAGES) do
   local ok, page = pcall(require, "pages." .. id)
   if ok and type(page) == "table" then
      table.insert(pages, page)
      local row = Gtk.ListBoxRow()
      local box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
      box:pack_start(Gtk.Image { icon_name = page.icon, pixel_size = 20 }, false, false, 0)
      box:pack_start(Gtk.Label { label = page.title, xalign = 0 }, true, true, 0)
      row:add(box)
      sidebar:add(row)
   else
      io.stderr:write("gobo-settings: page " .. id .. ": " .. tostring(page) .. "\n")
   end
end

local function show_page(i)
   local page = pages[i]
   if not page then return end
   if not built[page.id] then
      local ok, w = pcall(page.build, C)
      if not ok then w = C.text("This page could not be built:\n" .. tostring(w)) end
      stack:add_named(w, page.id)
      w:show_all()
      built[page.id] = true
   end
   stack:set_visible_child_name(page.id)
end

sidebar.on_row_selected = function(_, row)
   if row then show_page(row:get_index() + 1) end
end

local paned = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL }
paned:pack_start(side_scroll, false, false, 0)
paned:pack_start(Gtk.Separator { orientation = Gtk.Orientation.VERTICAL }, false, false, 0)
paned:pack_start(stack, true, true, 0)
window:add(paned)

-- Escape closes the window
window.on_key_press_event = function(_, event)
   if event.keyval == Gdk.KEY_Escape then window:destroy() return true end
   return false
end

window:show_all()
local function select_page(id)
   for i, page in ipairs(pages) do
      if page.id == id then sidebar:select_row(sidebar:get_row_at_index(i - 1)) return true end
   end
   return false
end
if not select_page(arg[1]) then sidebar:select_row(sidebar:get_row_at_index(0)) end

-- 0.8.2: a second "gobo-settings PAGE" raises this window (the launcher asks the desktop) and
-- writes PAGE into this file; switch to it
local page_file = C.HOME .. "/.cache/gobo-settings.page"
os.remove(page_file)
local page_monitor = C.Gio.File.new_for_path(page_file):monitor_file(C.Gio.FileMonitorFlags.NONE, nil)
if page_monitor then
   page_monitor.on_changed = function(_, _, _, event)
      if event ~= "CHANGES_DONE_HINT" and event ~= "CREATED" then return end
      local id = C.trim(C.read(page_file) or "")
      if id ~= "" then
         os.remove(page_file)
         select_page(id)
         window:present()
      end
   end
end
Gtk.main()
