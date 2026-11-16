-- 0.9.1: Simple accounts (members of the group "simple", Settings > Accounts).
-- A Simple account's menu, search and taskbar show only the programs chosen for it; the
-- terminal, the desktop's own tools and the keys that open them are left out (rc.lua).
-- This is for peace of mind, not a security boundary (docs/security.md): the boundary is file
-- permissions (private home folders) and no sudo.
--
-- The list of programs (desktop file names, one per line):
--   /Data/Variable/lib/gobo-settings/simple-apps/<login>   (written by Settings, as root)
--   else /Programs/GoboSpin/Current/share/gobo-settings/simple-apps.default
-- Read once at login. Settings is always allowed (it shows a Simple account only its own pages).
local M = {}

local function read_lines(path)
   local f = io.open(path, "r")
   if not f then return nil end
   local list = {}
   for line in f:lines() do
      line = line:gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:match("^#") then table.insert(list, line) end
   end
   f:close()
   return list
end

local function in_group(name)
   local p = io.popen("id -Gn 2>/dev/null")
   local s = p and p:read("*a") or ""
   if p then p:close() end
   for g in s:gmatch("%S+") do
      if g == name then return true end
   end
   return false
end

M.is_simple = in_group("simple")
M.user = os.getenv("USER") or ""

M.DEFAULT_FILE = "/Programs/GoboSpin/Current/share/gobo-settings/simple-apps.default"
M.USER_FILE = "/Data/Variable/lib/gobo-settings/simple-apps/" .. M.user
M.FALLBACK = { "firefox.desktop", "pcmanfm.desktop", "onlyoffice-desktopeditors.desktop", "l3afpad.desktop",
               "audacious.desktop" }

local app_dirs = {
   (os.getenv("HOME") or "") .. "/.local/share/applications",
   "/System/Index/share/applications",
   "/usr/share/applications",
}

-- the Name= of a desktop file (the first one without a language), or nil
local function desktop_name(id)
   for _, dir in ipairs(app_dirs) do
      local f = io.open(dir .. "/" .. id, "r")
      if f then
         local in_entry, name = false, nil
         for line in f:lines() do
            if line:match("^%[") then in_entry = (line == "[Desktop Entry]") end
            if in_entry and not name then name = line:match("^Name%s*=%s*(.-)%s*$") end
         end
         f:close()
         if name then return name end
      end
   end
   return nil
end

M.allowed_ids = {}
M.allowed_names = {}
if M.is_simple then
   local list = read_lines(M.USER_FILE) or read_lines(M.DEFAULT_FILE) or M.FALLBACK
   table.insert(list, "gobo-settings.desktop")
   for _, id in ipairs(list) do
      if id:match("^[%w][%w._+-]*%.desktop$") then
         M.allowed_ids[id] = true
         local name = desktop_name(id)
         if name then M.allowed_names[name] = true end
      end
   end
end

-- may this menu entry ({ name = ..., cmdline = ... } from menubar.menu_gen) be shown?
function M.allows(entry)
   if not M.is_simple then return true end
   return entry ~= nil and entry.name ~= nil and M.allowed_names[entry.name] == true
end

return M
