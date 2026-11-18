-- 0.9.5: "New" in the desktop's right-click menu: a folder, an empty text document or an empty
-- Word document in ~/Desktop, under a free name ("New folder", "New folder 2", ...), then a small
-- name prompt (zenity) to rename it. Cancel keeps the first name. PCManFM's desktop shows the new
-- item by itself (it watches the folder).
--
-- The Word document is a copy of a template shipped with the look (look/gobo11/templates, an
-- empty, valid .docx), on the image at /Programs/GoboSpin/Current/share/gobo11/templates.
local awful = require("awful")
local naughty = require("naughty")
local gears = require("gears")
local Gio = require("lgi").Gio

local M = {}

local home = os.getenv("HOME") or ""
M.dir = home .. "/Desktop"
M.templates = { "/Programs/GoboSpin/Current/share/gobo11/templates" }

local function exists(path)
   return Gio.File.new_for_path(path):query_exists(nil)
end

-- "New folder", "New folder 2", ... / "New text document.txt", "New text document 2.txt", ...
function M.free_name(base, ext)
   ext = ext or ""
   local name = base .. ext
   local i = 2
   while exists(M.dir .. "/" .. name) do
      name = string.format("%s %d%s", base, i, ext)
      i = i + 1
      if i > 999 then return nil end
   end
   return name
end

local function template(file)
   for _, d in ipairs(M.templates) do
      local p = d .. "/" .. file
      if gears.filesystem.file_readable(p) then return p end
   end
   return nil
end

local function copy(src, dst)
   local i = io.open(src, "rb")
   if not i then return false end
   local data = i:read("*a")
   i:close()
   local o = io.open(dst, "wb")
   if not o then return false end
   o:write(data)
   o:close()
   return true
end

local function fail(text)
   naughty.notify({ title = "Could not create the item", text = text, timeout = 8 })
end

-- a name the user typed: one path component, no "/" and not "." or ".."
local function valid_name(s)
   return s ~= "" and s ~= "." and s ~= ".." and not s:find("/", 1, true) and not s:find("%z")
      and #s <= 255
end

-- ask for a new name for M.dir/name (kind: "folder", "text document", "Word document")
local function rename_prompt(name, kind)
   awful.spawn.easy_async({ "zenity", "--entry", "--title=New " .. kind,
                            "--text=Name of the new " .. kind .. ":", "--entry-text=" .. name, "--width=360" },
      function(out, _, _, code)
         if code ~= 0 then return end   -- Cancel: keep the first name
         local new = (out or ""):gsub("\n$", "")
         if new == name or new == "" then return end
         if not valid_name(new) then
            fail("A name cannot contain \"/\" and cannot be empty, \".\" or \"..\". The item keeps the name \"" .. name .. "\".")
            return
         end
         if exists(M.dir .. "/" .. new) then
            fail("\"" .. new .. "\" already exists on the desktop. The item keeps the name \"" .. name .. "\".")
            return
         end
         local ok, err = os.rename(M.dir .. "/" .. name, M.dir .. "/" .. new)
         if not ok then fail(tostring(err)) end
      end)
end
M.rename_prompt = rename_prompt   -- lab tests

-- kind: "folder", "text" or "docx"; returns the created name (or nil)
function M.create(kind, ask)
   os.execute("mkdir -p '" .. M.dir:gsub("'", "'\\''") .. "'")
   local name, label
   if kind == "folder" then
      name, label = M.free_name("New folder"), "folder"
      if not name then return fail("No free name on the desktop.") end
      local ok, err = pcall(function() return Gio.File.new_for_path(M.dir .. "/" .. name):make_directory(nil) end)
      if not ok or not err then return fail("The folder could not be made.") end
   elseif kind == "text" then
      name, label = M.free_name("New text document", ".txt"), "text document"
      if not name then return fail("No free name on the desktop.") end
      local f = io.open(M.dir .. "/" .. name, "w")
      if not f then return fail("The file could not be written.") end
      f:close()
   elseif kind == "docx" then
      local src = template("New document.docx")
      if not src then return fail("The Word document template is missing.") end
      name, label = M.free_name("New document", ".docx"), "Word document"
      if not name then return fail("No free name on the desktop.") end
      if not copy(src, M.dir .. "/" .. name) then return fail("The file could not be written.") end
   else
      return nil
   end
   if ask ~= false then rename_prompt(name, label) end
   return name
end

return M
