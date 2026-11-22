-- GoboRefined 0.10.7: what an AppImage says about itself (name, icon, ...), read WITHOUT running it.
-- Used by appimage-install.lua ("Install", 0.10.6) and appimage-fixicons.lua (icons of AppImages
-- installed before 0.10.7). Needs lgi (GLib, Gio) and unsquashfs (4.6: gzip, xz, zstd); no GTK.
--
-- A type-2 AppImage is an ELF program (the runtime) with a SquashFS image appended. The image
-- starts where the ELF section table ends; runtimes without a section table (some static ones):
-- the first SquashFS superblock ("hsqs", version 4.0) in the first 4 MiB.
-- Icon, in this order: <Icon>.png/.svg at the top of the image, .DirIcon, then
-- usr/share/icons/hicolor/<size>/apps/<Icon>.png (the largest), .../scalable/apps/<Icon>.svg and
-- usr/share/pixmaps/<Icon>.png/.svg; links inside the image are followed (at most 4, never "..",
-- never absolute). Only PNG and SVG files (by content) count.
local lgi = require("lgi")
local GLib, Gio = lgi.GLib, lgi.Gio

local M = {}

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function sh(cmd) return os.execute(cmd .. " > /dev/null 2>&1") == true end
M.q, M.sh = q, sh

-- where the SquashFS image starts (nil: not a type-2 AppImage)
function M.offset(path)
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
      if off and off > 0 then
         f:seek("set", off)
         local sb = f:read(30) or ""
         if sb:sub(1, 4) ~= "hsqs" or #sb < 30 or string.unpack("<I2", sb, 29) ~= 4 then off = nil end
      else
         off = nil
      end
      if not off then   -- no usable section table: look for the superblock
         f:seek("set", 0)
         local data = f:read(4 * 1024 * 1024) or ""
         local pos = 1
         while true do
            local i = data:find("hsqs", pos, true)
            if not i then break end
            if i + 29 <= #data and string.unpack("<I2", data, i + 28) == 4 and string.unpack("<I2", data, i + 30) == 0 then
               off = i - 1
               break
            end
            pos = i + 1
         end
      end
   end
   f:close()
   return off
end

local function kind_of(path)   -- "png", "svg" or nil (by content)
   local f = io.open(path, "rb")
   if not f then return nil end
   local h = f:read(4096) or ""
   f:close()
   if h:sub(1, 8) == "\137PNG\r\n\26\n" then return "png" end
   if h:find("<svg", 1, true) then return "svg" end
   return nil
end

local function link_or_file(path)
   local ok, info = pcall(function()
      return Gio.File.new_for_path(path):query_info("standard::type,standard::is-symlink,standard::symlink-target",
         Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, nil)
   end)
   if not ok or not info then return nil end
   if info:get_is_symlink() then return "link", info:get_symlink_target() end
   return info:get_file_type() == "REGULAR" and "file" or nil
end

-- M.read(appimage): table { name, icon (Icon= value), comment, wmclass, categories, icon_file,
-- icon_kind } or nil; call M.cleanup(meta) when the icon file has been copied
function M.read(src)
   local offset = M.offset(src)
   if not offset then return nil end
   local tmp = GLib.dir_make_tmp("gobo-appimage-XXXXXX")
   if not tmp then return nil end
   local root = tmp .. "/root"
   local meta = { tmp = tmp, categories = {} }
   local function extract(patterns)
      local cmd = "unsquashfs -q -n -no-xattrs -f -d " .. q(root) .. " -o " .. string.format("%d", offset) .. " " .. q(src)
      for _, p in ipairs(patterns) do cmd = cmd .. " " .. q(p) end
      sh(cmd)
   end
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
   -- a path inside the image: follow links (relative, no "..") and extract what they point at
   local function resolve(rel)
      for _ = 1, 4 do
         local t, target = link_or_file(root .. "/" .. rel)
         if t == "file" then return root .. "/" .. rel end
         if t ~= "link" or not target or target:sub(1, 1) == "/" or target:find("..", 1, true) then return nil end
         local dir = rel:match("^(.*)/") or ""
         rel = (dir ~= "" and dir .. "/" or "") .. target
         extract({ rel })
      end
      return nil
   end
   local function try(rel)
      local p = resolve(rel)
      if p and kind_of(p) then meta.icon_file, meta.icon_kind = p, kind_of(p) return true end
   end
   local icon = meta.icon
   if icon and (icon:find("/") or icon:find("..", 1, true)) then icon = nil end
   if icon then icon = icon:gsub("%.png$", ""):gsub("%.svg$", "") end
   local found = (icon and (try(icon .. ".png") or try(icon .. ".svg"))) or try(".DirIcon")
   if not found and icon then
      extract({ "usr/share/icons/hicolor/*/apps/" .. icon .. ".png", "usr/share/icons/hicolor/scalable/apps/" .. icon .. ".svg",
                "usr/share/pixmaps/" .. icon .. ".png", "usr/share/pixmaps/" .. icon .. ".svg" })
      local best, best_size = nil, -1
      local hic = Gio.File.new_for_path(root .. "/usr/share/icons/hicolor")
      local en = hic:enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, nil)
      if en then
         while true do
            local info = en:next_file(nil)
            if not info then break end
            local size = tonumber((info:get_name():match("^(%d+)x%d+$")))
            if size and size > best_size and size <= 1024 then
               local rel = "usr/share/icons/hicolor/" .. info:get_name() .. "/apps/" .. icon .. ".png"
               if resolve(rel) then best, best_size = rel, size end
            end
         end
         en:close(nil)
      end
      found = (best and try(best)) or try("usr/share/icons/hicolor/scalable/apps/" .. icon .. ".svg")
         or try("usr/share/pixmaps/" .. icon .. ".png") or try("usr/share/pixmaps/" .. icon .. ".svg")
   end
   return meta
end

function M.cleanup(meta)
   if meta and meta.tmp and meta.tmp:match("/gobo%-appimage%-[%w]+$") then sh("rm -r -- " .. q(meta.tmp)) end
end

-- M.copy_icon(meta, folder): <folder>/icon.png|svg from the AppImage (old ones removed);
-- returns the file, or nil when the AppImage has no icon
function M.copy_icon(meta, folder)
   os.remove(folder .. "/icon.png")
   os.remove(folder .. "/icon.svg")
   if meta and meta.icon_file then
      local target = folder .. "/icon." .. meta.icon_kind
      if sh("cp -- " .. q(meta.icon_file) .. " " .. q(target)) then return target end
   end
   return nil
end

return M
