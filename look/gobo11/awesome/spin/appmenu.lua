-- 0.10.6: the start menu's list of programs, read the XDG way.
--
-- Awesome 4.3's menubar.menu_gen reads every applications folder at the same time and keeps the
-- first entry it sees for a "Name + command" pair, so a user's own copy of a desktop file in
-- ~/.local/share/applications did not reliably replace the system's one (NoDisplay=true in the
-- copy did not hide the program, changed Categories= could lose). This module replaces
-- menu_gen.generate (rc.lua installs it before anything asks for the list):
--   * desktop file ids as the XDG spec says (file name; sub-folders joined with "-"); the first
--     folder of XDG_DATA_HOME, XDG_DATA_DIRS that has an id wins and hides the others' file
--     with that id (so a user's copy with NoDisplay=true removes the program);
--   * an entry is in ONE category, the first main category of its Categories= (as before), but
--     a copy written by the start menu editor or the AppImage installer (key
--     X-GoboRefined-Menu=edited) is in EVERY main category it names: that is how "add to a
--     category" works without changing the default menu (spin/settings/menu-editor.lua uses
--     the same rule);
--   * sorted by name; read once and kept until reload() (rc.lua's spin_menu_reload()).
local gears = require("gears")
local menubar = require("menubar")
local menu_gen = require("menubar.menu_gen")
local Gio = require("lgi").Gio

local M = {}
M.EDITED_KEY = "X-GoboRefined-Menu"

-- main category name in Categories= -> menu_gen.all_categories key
local function key_of(app_type)
   for k, v in pairs(menu_gen.all_categories) do
      if v.app_type == app_type and v.use then return k end
   end
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
      if kind == "DIRECTORY" then
         list_dir(dir .. "/" .. name, prefix .. name .. "-", out)
      elseif name:match("%.desktop$") then
         table.insert(out, { id = prefix .. name, path = dir .. "/" .. name })
      end
   end
   enum:close(nil)
end

-- main categories in the order the file names them (unique); edited copies keep them all
function M.categories_of(program)
   local list, seen = {}, {}
   for _, c in ipairs(program.categories or {}) do
      local k = key_of(c)
      if k and not seen[k] then
         seen[k] = true
         table.insert(list, k)
      end
   end
   if program[M.EDITED_KEY] ~= "edited" and #list > 1 then list = { list[1] } end
   return list
end

local cache
function M.scan(force)
   if cache and not force then return cache end
   menu_gen.lookup_category_icons()
   local utils = menubar.utils
   local seen_id, seen_pair, result = {}, {}, {}
   for _, dir in ipairs(menu_gen.all_menu_dirs) do
      local files = {}
      list_dir((dir:gsub("/+$", "")), "", files)
      for _, f in ipairs(files) do
         if not seen_id[f.id] then
            seen_id[f.id] = true   -- the first folder with this id wins, shown or not
            local ok, p = pcall(utils.parse_desktop_file, f.path)
            if ok and p and p.show and not p.Hidden and p.Name and p.cmdline then
               local name = utils.rtrim(p.Name) or ""
               local cmdline = utils.rtrim(p.cmdline) or ""
               local pair = name .. "\0" .. cmdline
               if not seen_pair[pair] then
                  seen_pair[pair] = true
                  local cats = M.categories_of(p)
                  table.insert(result, { id = f.id, file = f.path, name = name, cmdline = cmdline,
                     icon = p.icon_path, category = cats[1], categories = cats,
                     edited = p[M.EDITED_KEY] == "edited" })
               end
            end
         end
      end
   end
   table.sort(result, function(a, b)
      local x, y = a.name:lower(), b.name:lower()
      if x ~= y then return x < y end
      return a.id < b.id
   end)
   cache = result
   return result
end

-- menu_gen.generate replacement: same callback, entries as above (synchronous, from the cache)
function M.install()
   menu_gen.generate = function(callback)
      local entries = M.scan()
      gears.protected_call(callback, entries)
   end
end

return M
