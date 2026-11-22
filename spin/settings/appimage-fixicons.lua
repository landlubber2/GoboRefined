-- GoboRefined 0.10.7: icons for AppImages installed with "Install" before 0.10.7 (gobo-appimage-install
-- --fix-icons; the session's .xinitrc runs it in the background at every login, as the user).
-- For each ~/.local/share/applications/appimage-*.desktop that names its folder in
-- X-GoboRefined-AppImage (a folder directly in ~/Applications) and has no X-GoboRefined-Icon=checked:
-- when its Icon= is not an image file that exists, the icon is read from the AppImage in that folder
-- (appimage-meta.lua, without running it) into <folder>/icon.png|svg and Icon= is set to it. The entry
-- then gets X-GoboRefined-Icon=checked (also when the AppImage has no icon: it keeps the generic one),
-- so this costs one folder listing per login afterwards. Changed entries: the start menu is read again.
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local lgi = require("lgi")
local GLib, Gio = lgi.GLib, lgi.Gio
local AM = require("appimage-meta")

local HOME = os.getenv("HOME") or ""
if HOME == "" or HOME == "/" then os.exit(0) end
local APPS_HOME = HOME .. "/Applications"
local USER_DIR = GLib.get_user_data_dir() .. "/applications"

local function exists_image(path)
   if not path or path:sub(1, 1) ~= "/" then return false end
   local f = io.open(path, "rb")
   if not f then return false end
   local h = f:read(4096) or ""
   f:close()
   return h:sub(1, 8) == "\137PNG\r\n\26\n" or h:find("<svg", 1, true) ~= nil
end

local changed = 0
local enum = Gio.File.new_for_path(USER_DIR):enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, nil)
if not enum then os.exit(0) end
local files = {}
while true do
   local info = enum:next_file(nil)
   if not info then break end
   local n = info:get_name()
   if n:match("^appimage%-[%w-]+%.desktop$") then table.insert(files, n) end
end
enum:close(nil)
table.sort(files)

local G = "Desktop Entry"
for _, n in ipairs(files) do
   local path = USER_DIR .. "/" .. n
   local kf = GLib.KeyFile()
   if kf:load_from_file(path, GLib.KeyFileFlags.KEEP_COMMENTS) and kf:has_group(G) then
      local folder = kf:get_string(G, "X-GoboRefined-AppImage")
      local checked = kf:get_string(G, "X-GoboRefined-Icon")
      local icon = kf:get_string(G, "Icon")
      -- only a folder directly in ~/Applications (the installer's own place), no odd characters
      local ok_folder = folder and folder:sub(1, #APPS_HOME + 1) == APPS_HOME .. "/"
         and not folder:sub(#APPS_HOME + 2):find("/") and not folder:find("..", 1, true) and not folder:find("[%c]")
      if ok_folder and checked ~= "checked" then
         if not exists_image(icon) then
            local appimage
            local en = Gio.File.new_for_path(folder):enumerate_children("standard::name,standard::type", Gio.FileQueryInfoFlags.NONE, nil)
            if en then
               while true do
                  local info = en:next_file(nil)
                  if not info then break end
                  if info:get_name():lower():match("%.appimage$") and info:get_file_type() == "REGULAR" then
                     appimage = folder .. "/" .. info:get_name()
                     break
                  end
               end
               en:close(nil)
            end
            if appimage then
               local meta = AM.read(appimage)
               local file = meta and AM.copy_icon(meta, folder)
               AM.cleanup(meta)
               if file then kf:set_string(G, "Icon", file) end
            end
         end
         kf:set_string(G, "X-GoboRefined-Icon", "checked")
         local data = kf:to_data()
         local f = io.open(path .. ".new", "w")
         if f then
            f:write(data)
            f:close()
            os.rename(path .. ".new", path)
            changed = changed + 1
         end
      end
   end
end
if changed > 0 then
   os.execute("awesome-client 'if spin_menu_reload then spin_menu_reload() end' > /dev/null 2>&1")
end
print(string.format("gobo-appimage-install --fix-icons: %d entries checked", changed))
