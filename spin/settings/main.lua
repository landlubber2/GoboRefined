-- GoboRefined Settings (gobo-settings): one window.
-- 0.9.2: overview of categories with a tile per page (like a phone's settings).
-- 0.9.4: also a tree look (sidebar categories; right pane = that category's tiles).
--        Default is tree; switch in the upper right; choice in
--        ~/.config/goborefined/settings-layout ("tree" or "overview").
-- Lua + lgi + GTK 3. Colours and font follow the GTK theme.
--
-- HOW TO ADD A PAGE: write pages/<id>.lua returning
--    { id = "<id>", title = "Title", icon = "<icon name>", build = function(C) return widget end }
-- (build runs the first time the page is shown; C = common.lua), add "<id>" to PAGES and to one
-- category in CATEGORIES below. Root work = new sub-command of gobo-settings-helper.
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-settings")
lgi.GLib.set_application_name("Settings")
local Gtk = lgi.require("Gtk", "3.0")
local Gdk = lgi.require("Gdk", "3.0")
local GLib = lgi.GLib
local C = require("common")

local PAGES = {
   "network", "bluetooth", "hotspot", "remote",
   "appearance", "hotkeys", "trash",
   "displays", "sound", "devices",
   "updates", "apps",
   "accounts", "about", "manual", "config",
}
local CATEGORIES = {
   { title = "Connectivity", icon = "network-wireless", pages = { "network", "bluetooth", "hotspot", "remote" } },
   { title = "Customization", icon = "preferences-desktop-theme", pages = { "appearance", "hotkeys", "trash" } },   -- 0.9.6: + hotkeys
   { title = "Devices", icon = "computer", pages = { "displays", "sound", "devices" } },
   { title = "Software", icon = "system-software-install", pages = { "updates", "apps" } },
   { title = "Accounts and system", icon = "system-users", pages = { "accounts", "about", "manual", "config" } },
}
local TILE_TITLE = { remote = "Remote access (SSH)", config = "Config (advanced)" }
local CATEGORY_OF = {}
for _, cat in ipairs(CATEGORIES) do for _, id in ipairs(cat.pages) do CATEGORY_OF[id] = cat.title end end

local KIND_PAGES = {
   simple   = { appearance = true, accounts = true, sound = true, about = true, manual = true },   -- 0.9.5: + manual
   standard = { appearance = true, accounts = true, sound = true, about = true,
                network = true, bluetooth = true, displays = true, trash = true,
                devices = true, apps = true, manual = true, config = true, hotkeys = true },   -- 0.9.5: + manual, config; 0.9.6: + hotkeys
}
do
   local allowed = KIND_PAGES[C.kind()]
   if allowed then
      local kept = {}
      for _, id in ipairs(PAGES) do if allowed[id] then table.insert(kept, id) end end
      PAGES = kept
   end
end

local LAYOUT_DIR = C.HOME .. "/.config/goborefined"
local LAYOUT_FILE = LAYOUT_DIR .. "/settings-layout"
local function read_layout()
   local v = C.trim(C.read(LAYOUT_FILE) or "")
   if v == "overview" or v == "tree" then return v end
   return "tree"
end
local function write_layout(name)
   GLib.mkdir_with_parents(LAYOUT_DIR, tonumber("0755", 8))
   local f = io.open(LAYOUT_FILE, "w")
   if f then f:write(name .. "\n"); f:close() end
end

local css = Gtk.CssProvider()
css:load_from_data([[
.gobo-tile { border-radius: 10px; padding: 8px; }
.gobo-topbar { padding: 4px 10px; }
.gobo-title { font-size: 20pt; font-weight: 600; }
.gobo-heading { font-size: 12pt; font-weight: 600; }
.gobo-value { font-weight: 600; }
.gobo-sidebar { background-color: alpha(@theme_fg_color, 0.04); }
.gobo-sidebar-row { padding: 10px 14px; border-radius: 6px; }
.gobo-layout-switch { padding: 4px 8px; }
]])
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

local window = Gtk.Window { title = "Settings", default_width = 1000, default_height = 680, icon_name = "preferences-system" }
window.on_destroy = Gtk.main_quit
C.window = window

local pages, built = {}, {}
for _, id in ipairs(PAGES) do
   local ok, page = pcall(require, "pages." .. id)
   if ok and type(page) == "table" then
      pages[id] = page
   else
      io.stderr:write("gobo-settings: page " .. id .. ": " .. tostring(page) .. "\n")
   end
end

local visible_cats, cat_index_of = {}, {}
for _, cat in ipairs(CATEGORIES) do
   local kept = {}
   for _, id in ipairs(cat.pages) do if pages[id] then table.insert(kept, id) end end
   if #kept > 0 then
      table.insert(visible_cats, { title = cat.title, icon = cat.icon or pages[kept[1]].icon, pages = kept })
      for _, id in ipairs(kept) do cat_index_of[id] = #visible_cats end
   end
end

-- Two looks (0.9.4), one widget tree:
--   tree      (default, like Windows 11): categories in a sidebar on the left that stays; the
--             right side shows the chosen category's tiles, and a tile's page opens there too
--   overview  every category with its tiles on one page; a page fills the window
-- The right side is one Gtk.Stack: "home" (overview), "cat" (one category's tiles), pages by id.
local nav = { layout = read_layout(), current = "home", cat = 1 }
local stack = Gtk.Stack { transition_type = Gtk.StackTransitionType.CROSSFADE, transition_duration = 120 }

-- top bar of the right side: back, where we are, the look switch
local back = Gtk.Button { relief = Gtk.ReliefStyle.NONE, halign = Gtk.Align.START, no_show_all = true }
local back_label = Gtk.Label { label = "All settings" }
do
   local b = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
   b:pack_start(Gtk.Image { icon_name = "go-previous-symbolic", pixel_size = 16 }, false, false, 0)
   b:pack_start(back_label, false, false, 0)
   back:add(b)
   b:show_all()
end
local crumb = Gtk.Label { xalign = 0 }
crumb:get_style_context():add_class("dim-label")
local layout_btn = Gtk.Button { relief = Gtk.ReliefStyle.NONE }
layout_btn:get_style_context():add_class("gobo-layout-switch")
local layout_btn_icon = Gtk.Image { pixel_size = 16 }
local layout_btn_label = Gtk.Label {}
do
   local b = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
   b:pack_start(layout_btn_icon, false, false, 0)
   b:pack_start(layout_btn_label, false, false, 0)
   layout_btn:add(b)
end
local topbar = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 10 }
topbar:get_style_context():add_class("gobo-topbar")
topbar:pack_start(back, false, false, 0)
topbar:pack_start(crumb, true, true, 0)
topbar:pack_end(layout_btn, false, false, 0)

local function make_tile(id)
   local page = pages[id]
   local tile = Gtk.Button { width_request = 176, height_request = 104 }
   tile:get_style_context():add_class("gobo-tile")
   local b = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 8, valign = Gtk.Align.CENTER }
   b:pack_start(Gtk.Image { icon_name = page.icon, pixel_size = 36 }, false, false, 0)
   b:pack_start(Gtk.Label { label = TILE_TITLE[id] or page.title, wrap = true,
      justify = Gtk.Justification.CENTER, max_width_chars = 16 }, false, false, 0)
   tile:add(b)
   tile.on_clicked = function() nav.select_page(id) end
   return tile
end
local function tile_flow(ids)
   local flow = Gtk.FlowBox { selection_mode = Gtk.SelectionMode.NONE, homogeneous = true,
      max_children_per_line = 6, min_children_per_line = 2, column_spacing = 10, row_spacing = 10,
      halign = Gtk.Align.START }
   for _, id in ipairs(ids) do flow:add(make_tile(id)) end
   return flow
end

-- overview: all categories
do
   local home = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6, margin = 28 }
   local t = Gtk.Label { label = "Settings", xalign = 0 }
   t:get_style_context():add_class("gobo-title")
   home:pack_start(t, false, false, 0)
   for _, cat in ipairs(visible_cats) do
      local h = C.heading(cat.title)
      h.margin_top = 18
      home:pack_start(h, false, false, 0)
      home:pack_start(tile_flow(cat.pages), false, false, 0)
   end
   local scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER }
   scroll:add(home)
   stack:add_named(scroll, "home")
end

-- tree: one category's tiles (rebuilt when another category is chosen)
local cat_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6, margin = 28 }
do
   local scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER }
   scroll:add(cat_box)
   stack:add_named(scroll, "cat")
end
local function fill_category(idx)
   for _, child in ipairs(cat_box:get_children()) do child:destroy() end
   local cat = visible_cats[idx]
   local t = Gtk.Label { label = cat.title, xalign = 0 }
   t:get_style_context():add_class("gobo-title")
   cat_box:pack_start(t, false, false, 0)
   cat_box:pack_start(tile_flow(cat.pages), false, false, 0)
   cat_box:show_all()
end

-- the sidebar (tree look only)
local sidebar = Gtk.ListBox { selection_mode = Gtk.SelectionMode.BROWSE }
sidebar:get_style_context():add_class("gobo-sidebar")
for _, cat in ipairs(visible_cats) do
   local row = Gtk.ListBoxRow {}
   local box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 10 }
   box:get_style_context():add_class("gobo-sidebar-row")
   box:pack_start(Gtk.Image { icon_name = cat.icon, pixel_size = 20 }, false, false, 0)
   box:pack_start(Gtk.Label { label = cat.title, xalign = 0 }, true, true, 0)
   row:add(box)
   sidebar:add(row)
end
local sidebar_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER, width_request = 230 }
sidebar_scroll:get_style_context():add_class("gobo-sidebar")
sidebar_scroll:add(sidebar)
local sidebar_box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL }
sidebar_box:pack_start(sidebar_scroll, true, true, 0)
sidebar_box:pack_start(Gtk.Separator { orientation = Gtk.Orientation.VERTICAL }, false, false, 0)

local function on_page() return nav.current ~= "home" and nav.current ~= "cat" end
local function refresh_chrome()
   local tree = nav.layout == "tree"
   sidebar_box.visible = tree
   layout_btn_icon.icon_name = tree and "view-grid-symbolic" or "view-list-symbolic"
   layout_btn_label.label = tree and "Overview" or "Tree"
   layout_btn.tooltip_text = tree and "Show all settings on one page" or "Show categories on the left"
   back.visible = on_page()
   back_label.label = tree and visible_cats[nav.cat].title or "All settings"
   if on_page() then
      crumb.label = (CATEGORY_OF[nav.current] or "") .. "  ›  " .. pages[nav.current].title
      window.title = pages[nav.current].title .. " - Settings"
   else
      crumb.label = ""
      window.title = "Settings"
   end
end

local selecting = false
local function select_sidebar_row(idx)
   local row = sidebar:get_row_at_index(idx - 1)
   if row and sidebar:get_selected_row() ~= row then
      selecting = true
      sidebar:select_row(row)
      selecting = false
   end
end

-- the starting view of the current look
function nav.show_home()
   if nav.layout == "tree" then
      fill_category(nav.cat)
      nav.current = "cat"
      stack:set_visible_child_name("cat")
      select_sidebar_row(nav.cat)
   else
      nav.current = "home"
      stack:set_visible_child_name("home")
   end
   refresh_chrome()
end

function nav.select_page(id)
   local page = pages[id]
   if not page then return false end
   if not built[id] then
      local ok, w = pcall(page.build, C)
      if not ok then w = C.text("This page could not be built:\n" .. tostring(w)) end
      stack:add_named(w, id)
      w:show_all()
      built[id] = true
   end
   nav.cat = cat_index_of[id] or nav.cat
   select_sidebar_row(nav.cat)
   nav.current = id
   stack:set_visible_child_name(id)
   refresh_chrome()
   return true
end

sidebar.on_row_selected = function(_, row)
   if selecting or not row then return end
   nav.cat = row:get_index() + 1
   nav.show_home()
end
back.on_clicked = function() nav.show_home() end
layout_btn.on_clicked = function()
   nav.layout = (nav.layout == "tree") and "overview" or "tree"
   write_layout(nav.layout)
   if on_page() then refresh_chrome() else nav.show_home() end
end

local right = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
right:pack_start(topbar, false, false, 0)
right:pack_start(Gtk.Separator { orientation = Gtk.Orientation.HORIZONTAL }, false, false, 0)
right:pack_start(stack, true, true, 0)
local outer = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL }
outer:pack_start(sidebar_box, false, false, 0)
outer:pack_start(right, true, true, 0)
window:add(outer)

-- Escape: back to the starting view, and from there it closes the window; Alt+Left goes back
window.on_key_press_event = function(_, event)
   if event.keyval == Gdk.KEY_Escape then
      if on_page() then nav.show_home() else window:destroy() end
      return true
   elseif event.keyval == Gdk.KEY_Left and event.state.MOD1_MASK and on_page() then
      nav.show_home()
      return true
   end
   return false
end

window:show_all()
nav.show_home()
if arg[1] and arg[1] ~= "" then nav.select_page(arg[1]) end

-- 0.8.2: a second "gobo-settings PAGE" raises this window (the launcher asks the desktop) and
-- writes PAGE into this file; switch to it ("home" = the starting view)
local page_file = C.HOME .. "/.cache/gobo-settings.page"
os.remove(page_file)
local page_monitor = C.Gio.File.new_for_path(page_file):monitor_file(C.Gio.FileMonitorFlags.NONE, nil)
if page_monitor then
   page_monitor.on_changed = function(_, _, _, event)
      if event ~= "CHANGES_DONE_HINT" and event ~= "CREATED" then return end
      local id = C.trim(C.read(page_file) or "")
      if id ~= "" then
         os.remove(page_file)
         if id == "home" then nav.show_home() else nav.select_page(id) end
         window:present()
      end
   end
end
Gtk.main()
