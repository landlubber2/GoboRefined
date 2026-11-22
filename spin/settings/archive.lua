-- GoboRefined 0.10.8: the file manager's archive actions (gobo-archive-gui), as the user:
--   --here FILE...      "Extract here": one top folder stays as it is, anything else goes into a
--                       new folder named after the archive ("name (2)" when it is taken)
--   --to FILE           "Extract to folder...": asks the folder's name (default: the archive's name)
--   --compress FILE...  "Compress...": name and format (zip default, tar.xz, 7z); the files must be
--                       in one folder (a file manager selection is)
--   --open FILE         a double click on an archive that is not a program: Extract here / to folder
-- The work is done by gobo-archive (safety rules there: no absolute paths, no "..", no device files,
-- no links pointing outside, free space checked). A small progress window appears when a job takes
-- longer than a moment; errors are shown in plain words.
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-archive")
lgi.GLib.set_application_name("Archives")
local Gtk = lgi.require("Gtk", "3.0")
local GLib, Gio = lgi.GLib, lgi.Gio
local C = require("common")

local ARCHIVE = "/System/Index/bin/gobo-archive"
local TITLE = "Archives"

local function message(text, secondary, kind)
   local d = Gtk.MessageDialog { modal = true, title = TITLE, message_type = kind or Gtk.MessageType.ERROR,
      window_position = Gtk.WindowPosition.CENTER, buttons = Gtk.ButtonsType.OK, text = text, secondary_text = secondary }
   d:run()
   d:destroy()
   while Gtk.events_pending() do Gtk.main_iteration() end
end
local function words(out)   -- gobo-archive's error in plain words
   local last = ""
   for line in tostring(out or ""):gmatch("[^\n]+") do if C.trim(line) ~= "" then last = line end end
   last = last:gsub("^gobo%-archive: ", "")
   return last ~= "" and (last:sub(1, 1):upper() .. last:sub(2)) or "Unknown error."
end
local function base_name(file)
   local b = file:match("([^/]+)$") or file
   local low = b:lower()
   for _, e in ipairs({ "%.tar%.gz$", "%.tar%.xz$", "%.tar%.bz2$", "%.tar%.zst$", "%.tar%.lz$", "%.tgz$", "%.txz$", "%.tbz2?$",
                        "%.tzst$", "%.tar$", "%.zip$", "%.7z$", "%.rar$", "%.gz$", "%.xz$", "%.bz2$", "%.zst$" }) do
      local s = low:find(e)
      if s then b = b:sub(1, s - 1) break end
   end
   return b ~= "" and b or "archive"
end
local function dir_of(path) return path:match("^(.*)/[^/]*$") or "." end
local function abs(path)
   if path:sub(1, 1) == "/" then return path end
   return GLib.get_current_dir() .. "/" .. path
end
local function exists(p) return Gio.File.new_for_path(p):query_exists(nil) end

-- run gobo-archive; a progress window when it takes longer than 0.7 s; returns ok, output
local function job(argv, text, cwd)
   local loop, ok, out, finished = GLib.MainLoop(), false, "", false
   local launcher = Gio.SubprocessLauncher.new({ "STDOUT_PIPE", "STDERR_MERGE" })
   launcher:setenv("LC_ALL", "C", true)
   if cwd then launcher:set_cwd(cwd) end
   local proc, err = launcher:spawnv(argv)
   if not proc then return false, tostring(err) end
   local win, bar, pulse
   GLib.timeout_add(GLib.PRIORITY_DEFAULT, 700, function()
      if finished then return false end
      win = Gtk.Window { title = TITLE, default_width = 380, resizable = false, deletable = false,
                         window_position = Gtk.WindowPosition.CENTER, icon_name = "package-x-generic" }
      local b = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 10, margin = 18 }
      b:pack_start(Gtk.Label { label = text, xalign = 0, ellipsize = "MIDDLE", max_width_chars = 50 }, false, false, 0)
      bar = Gtk.ProgressBar { pulse_step = 0.08 }
      b:pack_start(bar, false, false, 0)
      win:add(b)
      win:show_all()
      pulse = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, function() bar:pulse() return true end)
      return false
   end)
   proc:communicate_utf8_async(nil, nil, function(p, res)
      local o = p:communicate_utf8_finish(res)
      out = type(o) == "string" and o or ""
      ok = p:get_if_exited() and p:get_exit_status() == 0
      finished = true
      loop:quit()
   end)
   loop:run()
   if pulse then GLib.source_remove(pulse) end
   if win then win:destroy() end
   while Gtk.events_pending() do Gtk.main_iteration() end
   return ok, out
end

local function extract_here(file)
   file = abs(file)
   local ok, out = job({ ARCHIVE, "here", file, dir_of(file) }, "Extracting " .. (file:match("([^/]+)$") or file) .. " ...")
   if not ok then message("\"" .. (file:match("([^/]+)$") or file) .. "\" could not be extracted.", words(out)) end
   return ok
end

-- a dialog with one name field (and an optional format choice); returns name, format or nil
local function ask_name(title, text, default, formats)
   local d = Gtk.Dialog { title = title, modal = true, default_width = 440, resizable = false,
                          window_position = Gtk.WindowPosition.CENTER, icon_name = "package-x-generic" }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button(formats and "Compress" or "Extract", Gtk.ResponseType.OK)
   d:set_default_response(Gtk.ResponseType.OK)
   local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 10, margin = 18 }
   box:pack_start(Gtk.Label { label = text, xalign = 0, wrap = true, max_width_chars = 56 }, false, false, 0)
   local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
   local entry = Gtk.Entry { text = default, activates_default = true, hexpand = true }
   row:pack_start(entry, true, true, 0)
   local combo
   if formats then
      combo = Gtk.ComboBoxText()
      for _, f in ipairs(formats) do combo:append(f[1], f[2]) end
      combo:set_active_id(formats[1][1])
      row:pack_start(combo, false, false, 0)
   end
   box:pack_start(row, false, false, 0)
   d:get_content_area():pack_start(box, true, true, 0)
   box:show_all()
   entry:grab_focus()
   local r = d:run()
   local name, fmt = C.trim(entry.text), combo and combo:get_active_id()
   d:destroy()
   while Gtk.events_pending() do Gtk.main_iteration() end
   if r ~= Gtk.ResponseType.OK or name == "" then return nil end
   return name, fmt
end
local function bad_name(name)
   return name:find("/", 1, true) or name == "." or name == ".." or name:find("[%c]")
end
local function free_name(dir, name, ending)
   local n, i = name, 2
   while exists(dir .. "/" .. n .. (ending or "")) do n = name .. " (" .. i .. ")"; i = i + 1 end
   return n
end

local function extract_to(file)
   file = abs(file)
   local dir = dir_of(file)
   local name = ask_name("Extract to folder", "Extract \"" .. (file:match("([^/]+)$") or file) .. "\" into a new folder in "
      .. dir:gsub("^" .. C.HOME:gsub("%p", "%%%0"), "~") .. " named:", free_name(dir, base_name(file)))
   if not name then return end
   if bad_name(name) then return message("That name cannot be used for a folder.", "No \"/\" and no line breaks.") end
   if exists(dir .. "/" .. name) then return message("\"" .. name .. "\" already exists here.", "Choose another name.") end
   local ok, out = job({ ARCHIVE, "extract", file, dir .. "/" .. name }, "Extracting into " .. name .. " ...")
   if not ok then message("\"" .. (file:match("([^/]+)$") or file) .. "\" could not be extracted.", words(out)) end
end

local FORMATS = { { "zip", ".zip (works everywhere)" }, { "tar.xz", ".tar.xz (smaller, Linux)" }, { "7z", ".7z" } }
local function compress(files)
   local dir = dir_of(abs(files[1]))
   local rel = {}
   for _, f in ipairs(files) do
      f = abs(f)
      if dir_of(f) ~= dir then return message("The files must be in one folder.", f) end
      table.insert(rel, f:match("([^/]+)$"))
   end
   local default = #rel == 1 and (rel[1]:gsub("%.[^.]+$", "") ~= "" and rel[1]:gsub("%.[^.]+$", "") or rel[1]) or (dir:match("([^/]+)$") or "Archive")
   if #rel == 1 and exists(dir .. "/" .. rel[1]) and
      Gio.File.new_for_path(dir .. "/" .. rel[1]):query_file_type(Gio.FileQueryInfoFlags.NONE, nil) == "DIRECTORY" then
      default = rel[1]
   end
   local name, fmt = ask_name("Compress", (#rel == 1 and ("Pack \"" .. rel[1] .. "\"") or ("Pack " .. #rel .. " items"))
      .. " into an archive in " .. dir:gsub("^" .. C.HOME:gsub("%p", "%%%0"), "~") .. " named:", free_name(dir, default, ".zip"), FORMATS)
   if not name then return end
   for _, f in ipairs(FORMATS) do   -- a typed ending wins over the list
      if name:lower():sub(-#f[1] - 1) == "." .. f[1] then fmt = f[1]; name = name:sub(1, -#f[1] - 2) end
   end
   if bad_name(name) or name == "" then return message("That name cannot be used.", "No \"/\" and no line breaks.") end
   local out_name = name .. "." .. fmt
   if exists(dir .. "/" .. out_name) then return message("\"" .. out_name .. "\" already exists here.", "Choose another name.") end
   local argv = { ARCHIVE, "create", dir .. "/" .. out_name }
   for _, r in ipairs(rel) do table.insert(argv, r) end   -- gobo-archive passes them after "--"
   local ok, out = job(argv, "Packing " .. out_name .. " ...", dir)
   if not ok then message(out_name .. " could not be made.", words(out)) end
end

local function open(file)
   local d = Gtk.MessageDialog { modal = true, title = TITLE, message_type = Gtk.MessageType.QUESTION,
      window_position = Gtk.WindowPosition.CENTER, buttons = Gtk.ButtonsType.NONE,
      text = "Extract \"" .. (file:match("([^/]+)$") or file) .. "\"?",
      secondary_text = "This is an archive (packed files). Unpack it next to the archive, or into a folder you name." }
   d:add_button("Cancel", 1)
   d:add_button("Extract to folder...", 2)
   d:add_button("Extract here", 3)
   d:set_default_response(3)
   local r = d:run()
   d:destroy()
   while Gtk.events_pending() do Gtk.main_iteration() end
   if r == 3 then extract_here(file) elseif r == 2 then extract_to(file) end
end

local mode = arg[1]
local files = {}
for i = 2, #arg do table.insert(files, arg[i]) end
if #files == 0 then
   io.stderr:write("usage: gobo-archive-gui --here|--to|--compress|--open FILE...\n")
   os.exit(2)
end
if mode == "--here" then
   for _, f in ipairs(files) do extract_here(f) end
elseif mode == "--to" then
   extract_to(files[1])
elseif mode == "--compress" then
   compress(files)
elseif mode == "--open" then
   open(files[1])
else
   io.stderr:write("usage: gobo-archive-gui --here|--to|--compress|--open FILE...\n")
   os.exit(2)
end
