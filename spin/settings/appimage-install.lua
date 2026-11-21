-- GoboRefined 0.10.6: "Install" for AppImages (gobo-appimage-install FILE; the file manager's
-- right-click action on *.AppImage). Runs as the user and never needs a password.
--
--  1. Reads the AppImage's own .desktop file and icon WITHOUT running it: a type-2 AppImage is an
--     ELF program with a SquashFS image appended; the image starts where the ELF section table
--     ends, and unsquashfs (4.6, gzip/xz/zstd) extracts single files from that offset.
--  2. Name = the .desktop file's Name=, else the file name without version, architecture and
--     ".AppImage". Moves the file to ~/Applications/<Name>/ and makes it executable; the icon is
--     copied next to it (icon.png / icon.svg; a generic icon when the AppImage has none).
--     An app of that name already installed: asks before replacing its AppImage.
--  3. One dialog: add to the start menu in a category (default: the AppImage's own), pin it to
--     "Pinned and frequent", both, or neither (no shortcut).
-- The start menu entry is ~/.local/share/applications/appimage-<name>.desktop, marked
-- X-GoboRefined-Menu=edited (so the start menu editor can change it) and
-- X-GoboRefined-AppImage=<folder> (so the editor offers to delete the folder when it is removed).
-- Taskbar icons: rc.lua (0.10.3) reads the icon of icon-less AppImage windows from $APPDIR, so
-- it works the same for apps started from these entries.
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-appimage-install")
lgi.GLib.set_application_name("Install app")
local Gtk = lgi.require("Gtk", "3.0")
local GLib, Gio = lgi.GLib, lgi.Gio
local GdkPixbuf = lgi.require("GdkPixbuf", "2.0")
local C = require("common")

local TITLE = "Install app"
local APPS_HOME = C.HOME .. "/Applications"
local USER_DIR = GLib.get_user_data_dir() .. "/applications"
local PINS_DIR = C.HOME .. "/.config/goborefined"
local PINS = PINS_DIR .. "/start-pins"
local SLOTS = 8

-- start menu categories (as in menu-editor.lua / Awesome's menubar.menu_gen), menu order
local CATS = {
   { "Development", "Development" }, { "Education", "Education" }, { "Game", "Games" },
   { "Graphics", "Graphics" }, { "Network", "Internet" }, { "AudioVideo", "Multimedia" },
   { "Office", "Office" }, { "Science", "Science" }, { "Settings", "Settings" },
   { "System", "System Tools" }, { "Utility", "Accessories" },
}
local IS_MAIN = {}
for _, c in ipairs(CATS) do IS_MAIN[c[1]] = true end

local function say(text, secondary, kind)
   local d = Gtk.MessageDialog { modal = true, title = TITLE, message_type = kind or Gtk.MessageType.INFO,
      window_position = Gtk.WindowPosition.CENTER,
      buttons = Gtk.ButtonsType.OK, text = text, secondary_text = secondary }
   d:run()
   d:destroy()
end
local function fail(text, secondary)
   say(text, secondary, Gtk.MessageType.ERROR)
   os.exit(1)
end
local function ask(text, secondary, ok_label)
   local d = Gtk.MessageDialog { modal = true, title = TITLE, message_type = Gtk.MessageType.QUESTION,
      window_position = Gtk.WindowPosition.CENTER,
      buttons = Gtk.ButtonsType.NONE, text = text, secondary_text = secondary }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button(ok_label, Gtk.ResponseType.OK)
   d:set_default_response(Gtk.ResponseType.OK)
   local r = d:run()
   d:destroy()
   return r == Gtk.ResponseType.OK
end
local function sh(cmd) return os.execute(cmd .. " > /dev/null 2>&1") == true end
local function short(path)   -- ~/... for the dialogs
   if path:sub(1, #C.HOME + 1) == C.HOME .. "/" then return "~" .. path:sub(#C.HOME + 1) end
   return path
end

-- the file ------------------------------------------------------------------------------
if C.kind() == "simple" then fail("Apps cannot be installed in this account.") end
local src = arg[1] or ""
if src:sub(1, 1) ~= "/" then src = GLib.get_current_dir() .. "/" .. src end
local src_name = src:match("([^/]+)$") or ""
if not src_name:lower():match("%.appimage$") then fail("This is not an AppImage file.", src) end
do
   local info = Gio.File.new_for_path(src):query_info("standard::type", Gio.FileQueryInfoFlags.NONE, nil)
   if not info or info:get_file_type() ~= "REGULAR" then fail("The file was not found.", src) end
end
if src:sub(1, #APPS_HOME + 1) == APPS_HOME .. "/" then
   fail("This AppImage is already installed.", "It is in " .. short(src) .. ".")
end

-- where the SquashFS image starts (nil: not a type-2 AppImage)
local function squashfs_offset(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local h = f:read(64)
   local off
   if h and #h == 64 and h:sub(1, 4) == "\127ELF" and h:byte(6) == 1 then
      if h:byte(5) == 2 then
         local shoff = string.unpack("<I8", h, 0x29)
         local size, num = string.unpack("<I2I2", h, 0x3B)
         off = shoff + size * num
      elseif h:byte(5) == 1 then
         local shoff = string.unpack("<I4", h, 0x21)
         local size, num = string.unpack("<I2I2", h, 0x2F)
         off = shoff + size * num
      end
   end
   if off then
      f:seek("set", off)
      if f:read(4) ~= "hsqs" then off = nil end
   end
   f:close()
   return off
end

-- the AppImage's own .desktop and icon (into a private temporary folder)
local tmp = GLib.dir_make_tmp("gobo-appimage-XXXXXX")
local root = tmp .. "/root"
local function cleanup() if tmp and tmp:match("/gobo%-appimage%-[%w]+$") then sh("rm -r -- " .. C.q(tmp)) end end
local offset = squashfs_offset(src)
local function extract(patterns)
   local cmd = "unsquashfs -q -n -no-xattrs -f -d " .. C.q(root) .. " -o " .. string.format("%d", offset) .. " " .. C.q(src)
   for _, p in ipairs(patterns) do cmd = cmd .. " " .. C.q(p) end
   sh(cmd)
end
local function kind_of(path)   -- "png", "svg" or nil (by content)
   local f = io.open(path, "rb")
   if not f then return nil end
   local h = f:read(512) or ""
   f:close()
   if h:sub(1, 8) == "\137PNG\r\n\26\n" then return "png" end
   if h:find("<svg", 1, true) then return "svg" end
   return nil
end
local function regular(path)
   local info = Gio.File.new_for_path(path):query_info("standard::type,standard::is-symlink,standard::symlink-target",
      Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, nil)
   if not info then return nil end
   if info:get_is_symlink() then return "link", info:get_symlink_target() end
   return info:get_file_type() == "REGULAR" and "file" or nil
end

local meta = {}
if offset then
   extract({ "*.desktop", ".DirIcon", "*.png", "*.svg" })
   local desktop
   local enum = Gio.File.new_for_path(root):enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, nil)
   if enum then
      while true do
         local info = enum:next_file(nil)
         if not info then break end
         local n = info:get_name()
         if n:match("%.desktop$") and (not desktop or n < desktop) then desktop = n end
      end
      enum:close(nil)
   end
   if desktop then
      local kf = GLib.KeyFile()
      if kf:load_from_file(root .. "/" .. desktop, GLib.KeyFileFlags.NONE) and kf:has_group("Desktop Entry") then
         local G = "Desktop Entry"
         meta.name = kf:get_string(G, "Name")
         meta.icon = kf:get_string(G, "Icon")
         meta.comment = kf:get_string(G, "Comment")
         meta.wmclass = kf:get_string(G, "StartupWMClass")
         meta.categories = kf:get_string_list(G, "Categories") or {}
      end
   end
   -- the icon: <Icon>.png / .svg at the top, else .DirIcon (often a link into usr/share/icons)
   local cands = {}
   if meta.icon and not meta.icon:find("/") then
      table.insert(cands, root .. "/" .. meta.icon .. ".png")
      table.insert(cands, root .. "/" .. meta.icon .. ".svg")
   end
   local dir_icon = root .. "/.DirIcon"
   for _ = 1, 3 do   -- follow up to three links inside the image
      local t, target = regular(dir_icon)
      if t ~= "link" or not target or target:sub(1, 1) == "/" or target:find("%.%.") then break end
      local rel = (dir_icon:sub(#root + 2):match("^(.*)/") or "")
      rel = (rel ~= "" and rel .. "/" or "") .. target
      extract({ rel })
      dir_icon = root .. "/" .. rel
   end
   table.insert(cands, dir_icon)
   for _, p in ipairs(cands) do
      if regular(p) == "file" and kind_of(p) then meta.icon_file, meta.icon_kind = p, kind_of(p) break end
   end
end

-- the name and the folder ---------------------------------------------------------------
local function clean(s)
   s = tostring(s or ""):gsub("[%c\"$`\\%%]", ""):gsub("/", "-"):gsub("^[%s.]+", ""):gsub("%s+$", "")
   if #s > 60 then s = s:sub(1, 60):gsub("[\128-\255]+$", ""):gsub("%s+$", "") end
   return s
end
local name = clean(meta.name)
if name == "" then
   local n = src_name:gsub("%.[Aa][Pp][Pp][Ii][Mm][Aa][Gg][Ee]$", "")
   n = n:gsub("[-_.]x86[-_]64$", ""):gsub("[-_.]amd64$", ""):gsub("[-_.]x64$", "")
   n = n:gsub("[-_ ]v?%d[%w.+~-]*$", "")
   name = clean(n)
end
if name == "" then name = "App" end
local folder = APPS_HOME .. "/" .. name
local file_name = clean(src_name)
if file_name ~= src_name or file_name == "" then file_name = name .. ".AppImage" end
local dest = folder .. "/" .. file_name
local slug = name:lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
if slug == "" then slug = "app" end
local desktop_id = "appimage-" .. slug .. ".desktop"
local desktop_path = USER_DIR .. "/" .. desktop_id

-- an earlier install of this app: its AppImage file(s), menu entry and pin
local old_files = {}
do
   local enum = Gio.File.new_for_path(folder):enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, nil)
   if enum then
      while true do
         local info = enum:next_file(nil)
         if not info then break end
         if info:get_name():lower():match("%.appimage$") then table.insert(old_files, info:get_name()) end
      end
      enum:close(nil)
   end
end
local pins_text = C.read(PINS) or ""
local was_pinned = ("\n" .. pins_text):find("\napp\t" .. desktop_id:gsub("%p", "%%%0") .. "\n") ~= nil
local old_cat
do
   local kf = GLib.KeyFile()
   if kf:load_from_file(desktop_path, GLib.KeyFileFlags.NONE) then
      for _, c in ipairs(kf:get_string_list("Desktop Entry", "Categories") or {}) do
         if IS_MAIN[c] then old_cat = c break end
      end
      if kf:get_boolean("Desktop Entry", "NoDisplay") == true then old_cat = nil end
   end
end
if #old_files > 0 then
   if not ask("\"" .. name .. "\" is already installed.",
         "Replace " .. table.concat(old_files, ", ") .. " with " .. src_name .. "?", "Replace") then
      cleanup()
      os.exit(0)
   end
end

-- move it -------------------------------------------------------------------------------
GLib.mkdir_with_parents(folder, tonumber("0755", 8))
if not sh("mv -f -- " .. C.q(src) .. " " .. C.q(dest)) then
   cleanup()
   fail("The AppImage could not be moved to " .. short(folder) .. ".")
end
sh("chmod 755 -- " .. C.q(dest))
for _, f in ipairs(old_files) do
   if f ~= file_name then os.remove(folder .. "/" .. f) end
end
local icon = "application-x-executable"
os.remove(folder .. "/icon.png")
os.remove(folder .. "/icon.svg")
if meta.icon_file then
   local target = folder .. "/icon." .. meta.icon_kind
   if sh("cp -- " .. C.q(meta.icon_file) .. " " .. C.q(target)) then icon = target end
end
cleanup()

-- the dialog ----------------------------------------------------------------------------
local own_cat
for _, c in ipairs(meta.categories or {}) do
   if IS_MAIN[c] then own_cat = c break end
end
local first_install = #old_files == 0

local d = Gtk.Dialog { title = "Install " .. name, modal = true, default_width = 460, resizable = false,
                       window_position = Gtk.WindowPosition.CENTER, icon_name = "system-software-install" }
d:add_button("Done", Gtk.ResponseType.OK)
d:set_default_response(Gtk.ResponseType.OK)
local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 12, margin = 18 }
do
   local head = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 14 }
   local img
   if icon:sub(1, 1) == "/" then
      local ok, pb = pcall(GdkPixbuf.Pixbuf.new_from_file_at_size, icon, 48, 48)
      if ok and pb then img = Gtk.Image.new_from_pixbuf(pb) end
   end
   head:pack_start(img or Gtk.Image { icon_name = "application-x-executable", pixel_size = 48 }, false, false, 0)
   local t = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 4, valign = Gtk.Align.CENTER }
   t:pack_start(Gtk.Label { use_markup = true, xalign = 0,
      label = "<b>" .. GLib.markup_escape_text(name, -1) .. "</b> is installed." }, false, false, 0)
   local where = Gtk.Label { label = short(dest), xalign = 0, ellipsize = "MIDDLE", max_width_chars = 48 }
   where:get_style_context():add_class("dim-label")
   t:pack_start(where, false, false, 0)
   head:pack_start(t, true, true, 0)
   box:pack_start(head, false, false, 0)
end
box:pack_start(Gtk.Label { label = "Where should it be?", xalign = 0, margin_top = 6 }, false, false, 0)
local menu_check = Gtk.CheckButton { label = "In the start menu, under" }
local combo = Gtk.ComboBoxText()
for _, c in ipairs(CATS) do combo:append(c[1], c[2]) end
combo:set_active_id(old_cat or own_cat or "Utility")
menu_check.active = first_install or old_cat ~= nil
combo.sensitive = menu_check.active
menu_check.on_toggled = function() combo.sensitive = menu_check.active end
local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
row:pack_start(menu_check, false, false, 0)
row:pack_start(combo, false, false, 0)
box:pack_start(row, false, false, 0)
local pin_check = Gtk.CheckButton { label = "Pinned in \"Pinned and frequent\" (next to the start menu)", active = was_pinned }
box:pack_start(pin_check, false, false, 0)
local note = Gtk.Label { xalign = 0, wrap = true, max_width_chars = 56,
   label = "With neither, there is no shortcut: open the AppImage in its folder to start it. "
        .. "The start menu editor (right click on the start button) can change this later." }
note:get_style_context():add_class("dim-label")
box:pack_start(note, false, false, 0)
d:get_content_area():pack_start(box, true, true, 0)
box:show_all()
local done = d:run() == Gtk.ResponseType.OK
local in_menu, pinned, cat = menu_check.active, pin_check.active, combo:get_active_id()
if not done then   -- the window was closed: a new install gets no shortcut, a replaced one keeps its own
   in_menu, pinned, cat = old_cat ~= nil, was_pinned, old_cat
end
d:destroy()
while Gtk.events_pending() do Gtk.main_iteration() end

-- the menu entry and the pin --------------------------------------------------------------
if in_menu or pinned then
   local lines = {
      "[Desktop Entry]", "Type=Application", "Name=" .. name,
      "Exec=\"" .. dest .. "\" %U", "Icon=" .. icon, "Terminal=false",
      "Categories=" .. (in_menu and (cat .. ";") or ""),
   }
   local comment = clean(meta.comment)
   if comment ~= "" then table.insert(lines, "Comment=" .. comment) end
   local wmclass = clean(meta.wmclass)
   if wmclass ~= "" then table.insert(lines, "StartupWMClass=" .. wmclass) end
   table.insert(lines, "X-GoboRefined-Menu=edited")
   table.insert(lines, "X-GoboRefined-AppImage=" .. folder)
   GLib.mkdir_with_parents(USER_DIR, tonumber("0755", 8))
   local f = io.open(desktop_path .. ".new", "w")
   if f then
      f:write(table.concat(lines, "\n") .. "\n")
      f:close()
      os.rename(desktop_path .. ".new", desktop_path)
   else
      say("The start menu entry could not be written.", desktop_path, Gtk.MessageType.ERROR)
   end
else
   os.remove(desktop_path)
end

local pin_line = "app\t" .. desktop_id
local kept, count, have = {}, 0, false
for line in pins_text:gmatch("[^\n]+") do
   if line == pin_line then
      have = true
      if pinned then table.insert(kept, line); count = count + 1 end
   else
      table.insert(kept, line)
      if line:match("^%a+\t") then count = count + 1 end
   end
end
if pinned and not have then
   if count >= SLOTS then
      say("It could not be pinned.", string.format("All %d places are pinned. Unpin something first (right click on it in the start menu).", SLOTS))
   else
      table.insert(kept, pin_line)
   end
end
if pinned ~= have or (pinned and not have) then
   if #kept == 0 or not kept[1]:match("^#") then
      table.insert(kept, 1, "# GoboRefined start menu pins (kind<TAB>target), in pin order")
   end
   GLib.mkdir_with_parents(PINS_DIR, tonumber("0755", 8))
   local f = io.open(PINS .. ".new", "w")
   if f then f:write(table.concat(kept, "\n") .. "\n"); f:close(); os.rename(PINS .. ".new", PINS) end
end

-- the desktop reads the list again (first the apps, then the pins that may name the new one)
C.run({ "awesome-client", "if spin_menu_reload then spin_menu_reload() end; "
   .. "if spin_start_pins_reload then spin_start_pins_reload() end" }, nil, function() Gtk.main_quit() end)
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, function() Gtk.main_quit() return false end)
Gtk.main()
