-- GoboRefined 0.10.6: the start menu editor (gobo-menu-editor; a right click on the dots button).
--
-- Lists the start menu's categories and the apps in each. The user can add an installed app to a
-- category, remove it from a category, remove it from the start menu, and reset an app to its
-- default. Per user, the XDG way: a copy of the app's desktop file in
-- ~/.local/share/applications/ (same file name) with a changed Categories= (or NoDisplay=true),
-- marked "X-GoboRefined-Menu=edited". Copies live in the home folder, so they survive system
-- updates and rollbacks; "Reset" deletes the copy and the system's file counts again.
--
-- The same rules as the desktop's list (look/gobo11/awesome/spin/appmenu.lua): the first folder
-- (XDG_DATA_HOME, then XDG_DATA_DIRS) with a file name wins; an app is in the first main category
-- of its Categories=, an edited copy in every main category it names. After each change the
-- desktop reads the list again (awesome-client 'spin_menu_reload()'): no logging out.
--
-- Programs installed with the file manager's "Install" (gobo-install-app, 0.10.6/0.10.8) have a desktop
-- file of their own (key X-GoboRefined-AppImage=<folder>); removing one from the start menu offers
-- to delete its folder in ~/Applications too. Simple accounts have no editor (the wrapper and
-- the dots button refuse it).
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-menu-editor")
lgi.GLib.set_application_name("Start menu")
local Gtk = lgi.require("Gtk", "3.0")
local Gdk = lgi.require("Gdk", "3.0")
local GLib, Gio = lgi.GLib, lgi.Gio
local GdkPixbuf = lgi.require("GdkPixbuf", "2.0")
local C = require("common")

local TITLE = "Start menu"
local EDITED_KEY = "X-GoboRefined-Menu"
local APPIMAGE_KEY = "X-GoboRefined-AppImage"
local USER_DIR = GLib.get_user_data_dir() .. "/applications"
local APPS_HOME = C.HOME .. "/Applications"
local PINS = C.HOME .. "/.config/goborefined/start-pins"

-- the start menu's categories (Awesome 4.3 menubar.menu_gen.all_categories), in menu order
local CATS = {
   { key = "development", type = "Development", name = "Development", icon = "applications-development" },
   { key = "education", type = "Education", name = "Education", icon = "applications-science" },
   { key = "games", type = "Game", name = "Games", icon = "applications-games" },
   { key = "graphics", type = "Graphics", name = "Graphics", icon = "applications-graphics" },
   { key = "internet", type = "Network", name = "Internet", icon = "applications-internet" },
   { key = "multimedia", type = "AudioVideo", name = "Multimedia", icon = "applications-multimedia" },
   { key = "office", type = "Office", name = "Office", icon = "applications-office" },
   { key = "science", type = "Science", name = "Science", icon = "applications-science" },
   { key = "settings", type = "Settings", name = "Settings", icon = "applications-utilities" },
   { key = "tools", type = "System", name = "System Tools", icon = "applications-system" },
   { key = "utility", type = "Utility", name = "Accessories", icon = "applications-accessories" },
}
local CAT_BY_TYPE, CAT_BY_KEY = {}, {}
for _, c in ipairs(CATS) do CAT_BY_TYPE[c.type] = c; CAT_BY_KEY[c.key] = c end

if C.kind() == "simple" then
   C.message("The start menu cannot be changed in this account.")
   os.exit(1)
end

-- Reading the desktop files ---------------------------------------------------------------

local function menu_dirs()
   local dirs = { USER_DIR }
   local xdg = os.getenv("XDG_DATA_DIRS")
   if not xdg or xdg == "" then xdg = "/usr/local/share:/usr/share" end
   for d in xdg:gmatch("[^:]+") do table.insert(dirs, (d:gsub("/+$", "")) .. "/applications") end
   return dirs
end

local function list_dir(dir, prefix, out)
   local ok, enum = pcall(function()
      return Gio.File.new_for_path(dir):enumerate_children("standard::name,standard::type", Gio.FileQueryInfoFlags.NONE, nil)
   end)
   if not ok or not enum then return end
   while true do
      local info = enum:next_file(nil)
      if not info then break end
      local name, kind = info:get_name(), info:get_file_type()
      if kind == "DIRECTORY" then list_dir(dir .. "/" .. name, prefix .. name .. "-", out)
      elseif name:match("%.desktop$") then table.insert(out, { id = prefix .. name, path = dir .. "/" .. name }) end
   end
   enum:close(nil)
end

local function has(list, v)
   for _, x in ipairs(list or {}) do if x == v then return true end end
   return false
end

local function parse(path)
   local kf = GLib.KeyFile()
   if not kf:load_from_file(path, GLib.KeyFileFlags.NONE) then return nil end
   if not kf:has_group("Desktop Entry") then return nil end
   local G = "Desktop Entry"
   local function str(k) local v = kf:get_string(G, k); return v end
   local function bool(k) local v = kf:get_boolean(G, k); return v == true end
   local function list(k) local v = kf:get_string_list(G, k); return v or {} end
   local p = { name = str("Name"), exec = str("Exec"), icon = str("Icon"), categories = list("Categories"),
               nodisplay = bool("NoDisplay"), hidden = bool("Hidden"), edited = str(EDITED_KEY) == "edited",
               appimage = str(APPIMAGE_KEY), type = str("Type") }
   if not p.name or p.name == "" or not p.exec then return nil end
   if p.type and p.type ~= "Application" then return nil end
   -- the desktop (Awesome) shows OnlyShowIn=...awesome... and hides NotShowIn=...awesome...
   local only, never = list("OnlyShowIn"), list("NotShowIn")
   p.show = not p.nodisplay and not p.hidden and (#only == 0 or has(only, "awesome")) and not has(never, "awesome")
   -- main categories: the first one only, all of them in an edited copy (spin/appmenu.lua)
   p.cats = {}
   for _, t in ipairs(p.categories) do
      local c = CAT_BY_TYPE[t]
      if c and not has(p.cats, c.key) then table.insert(p.cats, c.key) end
   end
   if not p.edited and #p.cats > 1 then p.cats = { p.cats[1] } end
   return p
end

local apps = {}   -- every app the menu could show, plus the ones hidden through a copy
local function scan()
   apps = {}
   local seen_id, seen_pair, sys_of = {}, {}, {}
   local dirs = menu_dirs()
   for i, dir in ipairs(dirs) do
      local files = {}
      list_dir(dir, "", files)
      for _, f in ipairs(files) do
         if i > 1 and not sys_of[f.id] then sys_of[f.id] = f.path end
         if not seen_id[f.id] then
            seen_id[f.id] = true
            local p = parse(f.path)
            if p then
               p.id, p.path, p.user = f.id, f.path, (i == 1)
               local pair = p.name .. "\0" .. p.exec
               if p.show and seen_pair[pair] then p = nil end
               if p and (p.show or (p.user and p.edited)) then
                  if p.show then seen_pair[pair] = true end
                  table.insert(apps, p)
               end
            end
         end
      end
   end
   for _, a in ipairs(apps) do a.sys_path = sys_of[a.id] end
   table.sort(apps, function(a, b)
      local x, y = a.name:lower(), b.name:lower()
      if x ~= y then return x < y end
      return a.id < b.id
   end)
end

-- Writing the copies --------------------------------------------------------------------

local function tell_desktop()
   C.spawn({ "awesome-client", "if spin_menu_reload then spin_menu_reload() end" })
end

-- write ~/.local/share/applications/<id> from the app's current file with these main categories
-- (keys) and NoDisplay; every other line is kept as it is
local function write_copy(app, mains, nodisplay)
   local text = C.read(app.path)
   if not text then C.error("Could not read " .. app.path) return false end
   local tokens = {}
   for _, t in ipairs(app.categories) do
      if not CAT_BY_TYPE[t] and t ~= "" then table.insert(tokens, t) end
   end
   for _, k in ipairs(mains) do table.insert(tokens, CAT_BY_KEY[k].type) end
   local ours = { "Categories=" .. table.concat(tokens, ";") .. (#tokens > 0 and ";" or "") }
   if nodisplay then table.insert(ours, "NoDisplay=true") end
   table.insert(ours, EDITED_KEY .. "=edited")

   local out, group, done = {}, nil, false
   local function put_ours() if not done then for _, l in ipairs(ours) do table.insert(out, l) end; done = true end end
   for line in (text:gsub("\r", "") .. (text:sub(-1) == "\n" and "" or "\n")):gmatch("(.-)\n") do
      local g = line:match("^%[(.*)%]%s*$")
      if g then
         if group == "Desktop Entry" then
            while out[#out] == "" do table.remove(out) end
            put_ours()
            table.insert(out, "")
         end
         group = g
         table.insert(out, line)
      elseif group == "Desktop Entry" and (line:match("^Categories%s*=") or line:match("^NoDisplay%s*=")
            or line:match("^Hidden%s*=") or line:match("^" .. EDITED_KEY .. "%s*=")) then
         -- replaced by ours
      else
         table.insert(out, line)
      end
   end
   if group == "Desktop Entry" then put_ours() end
   if not done then C.error("Not a desktop file: " .. app.path) return false end

   GLib.mkdir_with_parents(USER_DIR, tonumber("0755", 8))
   local target = USER_DIR .. "/" .. app.id
   local tmp = target .. ".new"
   local f = io.open(tmp, "w")
   if not f then C.error("Could not write " .. target) return false end
   f:write(table.concat(out, "\n") .. "\n")
   f:close()
   local ok, err = os.rename(tmp, target)
   if not ok then os.remove(tmp); C.error("Could not write " .. target .. ":\n" .. tostring(err)) return false end
   return true
end

local function without(list, v)
   local out = {}
   for _, x in ipairs(list) do if x ~= v then table.insert(out, x) end end
   return out
end

local function cat_names(keys, skip)
   local names = {}
   for _, k in ipairs(keys) do if k ~= skip then table.insert(names, CAT_BY_KEY[k].name) end end
   return table.concat(names, ", ")
end

-- an AppImage's folder, only when it is ~/Applications/<one name> and a real folder
local function appimage_folder(app)
   local dir = app.appimage
   if not dir or not app.user then return nil end
   dir = dir:gsub("/+$", "")
   local name = dir:sub(#APPS_HOME + 2)
   if dir:sub(1, #APPS_HOME + 1) ~= APPS_HOME .. "/" or name == "" or name:find("/") or name == "." or name == ".." then
      return nil
   end
   local info = Gio.File.new_for_path(dir):query_info("standard::type,standard::is-symlink", Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, nil)
   if not info or info:get_file_type() ~= "DIRECTORY" or info:get_is_symlink() then return nil end
   return dir, name
end

local function unpin(id)
   local text = C.read(PINS)
   if not text then return end
   local out, changed = {}, false
   for line in text:gmatch("[^\n]+") do
      if line == "app\t" .. id then changed = true else table.insert(out, line) end
   end
   if changed then
      local f = io.open(PINS .. ".new", "w")
      if f then f:write(table.concat(out, "\n") .. "\n"); f:close(); os.rename(PINS .. ".new", PINS) end
      C.spawn({ "awesome-client", "if spin_start_pins_reload then spin_start_pins_reload() end" })
   end
end

-- Dialogs (titled like this window) -----------------------------------------------------

local window
local function ask(text, secondary, ok_label, check_label)
   local d = Gtk.MessageDialog { transient_for = window, modal = true, destroy_with_parent = true, title = TITLE,
      message_type = Gtk.MessageType.QUESTION, buttons = Gtk.ButtonsType.NONE, text = text, secondary_text = secondary }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button(ok_label, Gtk.ResponseType.OK)
   d:set_default_response(Gtk.ResponseType.CANCEL)
   local check
   if check_label then
      check = Gtk.CheckButton { label = check_label }
      d:get_message_area():pack_start(check, false, false, 0)
      check:show()
   end
   local r = d:run()
   local checked = check and check.active
   d:destroy()
   return r == Gtk.ResponseType.OK, checked
end

local function icon_image(icon, size)
   size = size or 24
   if icon and icon:sub(1, 1) == "/" then
      local ok, pb = pcall(GdkPixbuf.Pixbuf.new_from_file_at_size, icon, size, size)
      if ok and pb then return Gtk.Image.new_from_pixbuf(pb) end
      icon = nil
   end
   if icon then icon = icon:gsub("%.[Pp][Nn][Gg]$", ""):gsub("%.[Ss][Vv][Gg]$", ""):gsub("%.[Xx][Pp][Mm]$", "") end   -- Icon=firefox.png
   if icon and icon ~= "" and Gtk.IconTheme.get_default():has_icon(icon) then
      return Gtk.Image { icon_name = icon, pixel_size = size }
   end
   return Gtk.Image { icon_name = "application-x-executable", pixel_size = size }
end

-- The window ----------------------------------------------------------------------------

local css = Gtk.CssProvider()
css:load_from_data([[
.gobo-title { font-size: 20pt; font-weight: 600; }
.gobo-sidebar { background-color: alpha(@theme_fg_color, 0.04); }
.gobo-sidebar-row { padding: 10px 14px; border-radius: 6px; }
.gobo-app-row { padding: 6px 10px; }
.gobo-count { font-size: smaller; }
]])
Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

window = Gtk.Window { title = TITLE, default_width = 920, default_height = 640, icon_name = "view-list" }
window.on_destroy = Gtk.main_quit
C.window = window

-- views: the categories, then "Other apps" (search only) and "Hidden apps"
local VIEWS = {}
for _, c in ipairs(CATS) do table.insert(VIEWS, { key = c.key, name = c.name, icon = c.icon }) end
table.insert(VIEWS, { key = "other", name = "Other apps", icon = "applications-other", special = true,
   intro = "Installed apps that are in no category: the search finds them, the menu does not list them. Add one to a category, or remove it." })
table.insert(VIEWS, { key = "hidden", name = "Hidden apps", icon = "view-hidden", special = true,
   intro = "Apps you removed from the start menu. They are still installed; \"Show again\" brings one back." })
local current = 1

local function apps_in(view)
   local list = {}
   for _, a in ipairs(apps) do
      if view.key == "hidden" then
         if not a.show then table.insert(list, a) end
      elseif view.key == "other" then
         if a.show and #a.cats == 0 then table.insert(list, a) end
      elseif a.show and has(a.cats, view.key) then
         table.insert(list, a)
      end
   end
   return list
end

local sidebar = Gtk.ListBox { selection_mode = Gtk.SelectionMode.BROWSE }
sidebar:get_style_context():add_class("gobo-sidebar")
local count_labels = {}
for i, v in ipairs(VIEWS) do
   local row = Gtk.ListBoxRow {}
   local box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 10 }
   box:get_style_context():add_class("gobo-sidebar-row")
   box:pack_start(Gtk.Image { icon_name = v.icon, pixel_size = 20 }, false, false, 0)
   box:pack_start(Gtk.Label { label = v.name, xalign = 0 }, true, true, 0)
   count_labels[i] = Gtk.Label { xalign = 1 }
   count_labels[i]:get_style_context():add_class("dim-label")
   count_labels[i]:get_style_context():add_class("gobo-count")
   box:pack_end(count_labels[i], false, false, 0)
   if i == #CATS + 1 then   -- a line between the categories and the two other lists
      local sep = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }
      sep:pack_start(Gtk.Separator { orientation = Gtk.Orientation.HORIZONTAL, margin_top = 6, margin_bottom = 6 }, false, false, 0)
      sep:pack_start(box, false, false, 0)
      row:add(sep)
   else
      row:add(box)
   end
   sidebar:add(row)
end
local sidebar_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER, width_request = 250 }
sidebar_scroll:get_style_context():add_class("gobo-sidebar")
sidebar_scroll:add(sidebar)

local right = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 14, margin = 28 }
local title = Gtk.Label { xalign = 0 }
title:get_style_context():add_class("gobo-title")
local intro = C.text("")
intro:get_style_context():add_class("dim-label")
local add_btn = Gtk.Button { label = "Add an app...", halign = Gtk.Align.START }
local list_box = Gtk.ListBox { selection_mode = Gtk.SelectionMode.NONE }
local list_frame = Gtk.Frame {}
list_frame:add(list_box)
local list_scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true }
list_scroll:add(list_frame)
local foot = C.text("Changes are for your account only, show in the start menu at once and stay after system updates.")
foot:get_style_context():add_class("dim-label")
right:pack_start(title, false, false, 0)
right:pack_start(intro, false, false, 0)
right:pack_start(add_btn, false, false, 0)
right:pack_start(list_scroll, true, true, 0)
right:pack_start(foot, false, false, 0)

local fill   -- forward

local function changed()
   scan()
   fill()
   tell_desktop()
end

local function remove_from_menu(app)
   local folder, fname = appimage_folder(app)
   local secondary = folder and "Its menu entry goes away. The app itself stays in ~/Applications/" .. fname .. " unless you tick the box."
      or "The app stays installed. \"Hidden apps\" can bring it back."
   local ok, delete = ask("Remove \"" .. app.name .. "\" from the start menu?", secondary, "Remove",
      folder and ("Also delete the app (the folder ~/Applications/" .. fname .. ")") or nil)
   if not ok then return end
   if folder and delete then
      -- folder: checked by appimage_folder (~/Applications/<one name>, a real folder)
      if not os.execute("rm -r -- " .. C.q(folder)) then C.error("Could not delete " .. folder .. ".") return end
      os.remove(app.path)
      unpin(app.id)
      changed()
      return
   end
   if write_copy(app, app.cats, true) then
      unpin(app.id)   -- a hidden app cannot be started from the panel either
      changed()
   end
end

local function remove_from(app, key)
   if #app.cats > 1 then
      if write_copy(app, without(app.cats, key), false) then changed() end
   else
      remove_from_menu(app)
   end
end

local function reset(app)
   if app.user and app.sys_path then
      os.remove(app.path)
      changed()
   end
end

local function show_again(app)
   if app.sys_path then reset(app)
   elseif write_copy(app, app.cats, false) then changed() end
end

local function app_row(app, view)
   local row = Gtk.ListBoxRow { activatable = false }
   local box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
   box:get_style_context():add_class("gobo-app-row")
   box:pack_start(icon_image(app.icon, 28), false, false, 0)
   local texts = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 2, valign = Gtk.Align.CENTER }
   texts:pack_start(Gtk.Label { label = app.name, xalign = 0, ellipsize = "END" }, false, false, 0)
   local notes = {}
   if not view.special and #app.cats > 1 then table.insert(notes, "Also in " .. cat_names(app.cats, view.key)) end
   if app.appimage then table.insert(notes, "Installed in ~/Applications")
   elseif app.user and app.sys_path then table.insert(notes, "Changed by you")
   elseif app.user then table.insert(notes, "Your own entry") end
   if #notes > 0 then
      local n = Gtk.Label { label = table.concat(notes, "  ·  "), xalign = 0, ellipsize = "END" }
      n:get_style_context():add_class("dim-label")
      n:get_style_context():add_class("gobo-count")
      texts:pack_start(n, false, false, 0)
   end
   box:pack_start(texts, true, true, 0)
   local function button(label, tip, fn)
      local b = Gtk.Button { label = label, valign = Gtk.Align.CENTER, tooltip_text = tip }
      b.on_clicked = function() fn() end
      box:pack_end(b, false, false, 0)
   end
   if view.key == "hidden" then
      button("Show again", "Put it back in the start menu", function() show_again(app) end)
   elseif view.key == "other" then
      button("Remove", "Remove it from the start menu and the search", function() remove_from_menu(app) end)
   else
      button("Remove", #app.cats > 1 and ("Remove it from " .. view.name .. " (it stays in " .. cat_names(app.cats, view.key) .. ")")
         or "Remove it from the start menu", function() remove_from(app, view.key) end)
   end
   if view.key ~= "hidden" and app.user and app.sys_path then
      button("Reset", "Back to the default (delete your changed copy)", function() reset(app) end)
   end
   row:add(box)
   return row
end

fill = function()
   for i, v in ipairs(VIEWS) do
      local n = #apps_in(v)
      count_labels[i].label = (n > 0 or not v.special) and tostring(n) or ""
   end
   local view = VIEWS[current]
   title.label = view.name
   intro.label = view.intro or "The apps in this category of the start menu."
   add_btn.visible = not view.special
   add_btn.label = "Add an app to " .. view.name .. "..."
   C.clear(list_box)
   local list = apps_in(view)
   for _, a in ipairs(list) do list_box:add(app_row(a, view)) end
   if #list == 0 then
      local l = Gtk.Label { label = view.special and "None." or "No apps in this category. The start menu leaves it out.",
                            xalign = 0, margin = 14 }
      l:get_style_context():add_class("dim-label")
      local r = Gtk.ListBoxRow { activatable = false }
      r:add(l)
      list_box:add(r)
   end
   list_box:show_all()
end

-- "Add an app to <category>": every app that is not in it yet, with a search field
local function add_dialog()
   local view = VIEWS[current]
   local d = Gtk.Dialog { title = "Add an app to " .. view.name, transient_for = window, modal = true,
                          default_width = 520, default_height = 560 }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   local ok_btn = d:add_button("Add", Gtk.ResponseType.OK)
   ok_btn.sensitive = false
   local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 10, margin = 14 }
   local search = Gtk.SearchEntry { placeholder_text = "Search apps" }
   local lb = Gtk.ListBox { selection_mode = Gtk.SelectionMode.SINGLE, activate_on_single_click = false }
   local scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER, vexpand = true }
   scroll:add(lb)
   local frame = Gtk.Frame {}
   frame:add(scroll)
   box:pack_start(search, false, false, 0)
   box:pack_start(frame, true, true, 0)
   d:get_content_area():pack_start(box, true, true, 0)
   local row_app = {}
   for _, a in ipairs(apps) do
      if not (a.show and has(a.cats, view.key)) then
         local row = Gtk.ListBoxRow {}
         local rb = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 10, margin = 6 }
         rb:pack_start(icon_image(a.icon, 24), false, false, 0)
         rb:pack_start(Gtk.Label { label = a.name, xalign = 0 }, true, true, 0)
         local where = not a.show and "hidden" or (#a.cats > 0 and cat_names(a.cats) or "no category")
         local w = Gtk.Label { label = where, xalign = 1 }
         w:get_style_context():add_class("dim-label")
         w:get_style_context():add_class("gobo-count")
         rb:pack_end(w, false, false, 0)
         row:add(rb)
         lb:add(row)
         row_app[row:get_index()] = a
      end
   end
   lb:set_filter_func(function(row)
      local q = search.text:lower()
      local a = row_app[row:get_index()]
      return q == "" or (a and a.name:lower():find(q, 1, true) ~= nil)
   end)
   search.on_search_changed = function() lb:invalidate_filter() end
   lb.on_row_selected = function(_, row) ok_btn.sensitive = row ~= nil end
   lb.on_row_activated = function() d:response(Gtk.ResponseType.OK) end
   box:show_all()
   local chosen
   if d:run() == Gtk.ResponseType.OK then
      local row = lb:get_selected_row()
      chosen = row and row_app[row:get_index()]
   end
   d:destroy()
   if not chosen then return end
   local mains = {}
   for _, k in ipairs(chosen.show and chosen.cats or {}) do table.insert(mains, k) end
   if not chosen.show then mains = {} end
   table.insert(mains, view.key)
   if write_copy(chosen, mains, false) then changed() end
end
add_btn.on_clicked = add_dialog

sidebar.on_row_selected = function(_, row)
   if not row then return end
   current = row:get_index() + 1
   fill()
end

local outer = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL }
outer:pack_start(sidebar_scroll, false, false, 0)
outer:pack_start(Gtk.Separator { orientation = Gtk.Orientation.VERTICAL }, false, false, 0)
outer:pack_start(right, true, true, 0)
window:add(outer)
window.on_key_press_event = function(_, event)
   if event.keyval == Gdk.KEY_Escape then window:destroy() return true end
   return false
end

scan()
-- start on the first category that has apps (the list box selects its first row when shown)
local first = 1
for i, v in ipairs(VIEWS) do
   if #apps_in(v) > 0 then first = i break end
end
window:show_all()
current = first
sidebar:select_row(sidebar:get_row_at_index(first - 1))
fill()
Gtk.main()
