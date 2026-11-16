-- Apps (0.9.2): add a program from a GoboLinux package file (Name--Version--x86_64.tar.bz2, the
-- format of GoboLinux's own CreatePackage / InstallPackage), after checking that it fits this
-- system (gobo-app-check: architecture, programs it depends on, libraries, C library version).
-- The file can come from a folder, a USB stick, or an FTP server (anonymous), through one
-- browser window. Installing and removing: gobo-settings-helper app-install / app-remove.
local P = { id = "apps", title = "Apps", icon = "system-software-install" }

local LIST = "/Data/Variable/lib/gobo-settings/apps.list"
local function is_package(name)
   local ext = name:match("^[%w][%w+_.~-]*%-%-[%w][%w+_.~-]*%-%-[%w_]+%.tar%.(%w+)$")
   return ext == "bz2" or ext == "gz" or ext == "xz" or ext == "zst"
end
local function valid_ftp(url)
   return url:match("^ftp://[%w][%w.-]*/[%w ._+~/-]*$") ~= nil or url:match("^ftp://[%w][%w.-]*:%d+/[%w ._+~/-]*$") ~= nil
end

-- One window to pick a package: local folders and FTP folders. Returns a local file path
-- (an FTP file is downloaded into ~/Downloads first) or nil.
local function browse(C)
   local Gtk, GLib = C.Gtk, C.GLib
   local GObject = require("lgi").GObject
   local d = Gtk.Dialog { title = "Choose a package file", transient_for = C.window, modal = true, default_width = 720, default_height = 520 }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   local ok_btn = d:add_button("Choose", Gtk.ResponseType.OK)
   ok_btn.sensitive = false
   local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 8, margin = 12 }
   local entry = Gtk.Entry { hexpand = true, placeholder_text = "A folder (/Users/...) or an FTP address (ftp://server/folder/)" }
   local status = Gtk.Label { xalign = 0, wrap = true }
   status:get_style_context():add_class("dim-label")
   local COL = { ICON = 1, NAME = 2, SIZE = 3, KIND = 4 }
   local store = Gtk.ListStore.new { GObject.Type.STRING, GObject.Type.STRING, GObject.Type.STRING, GObject.Type.STRING }
   local view = Gtk.TreeView { model = store, headers_visible = true }
   view:append_column(Gtk.TreeViewColumn { title = "", { Gtk.CellRendererPixbuf {}, { icon_name = COL.ICON } } })
   view:append_column(Gtk.TreeViewColumn { title = "Name", expand = true,
      { Gtk.CellRendererText {}, { text = COL.NAME }, expand = true } })
   view:append_column(Gtk.TreeViewColumn { title = "Size", { Gtk.CellRendererText { xalign = 1 }, { text = COL.SIZE } } })
   local scroll = Gtk.ScrolledWindow { vexpand = true }
   scroll:add(view)

   local here = C.HOME .. "/Downloads"
   if not C.exists(here) then here = C.HOME end
   local chosen, load

   local function human(n)
      n = tonumber(n) or 0
      if n >= 1e9 then return string.format("%.1f GB", n / 1e9) elseif n >= 1e6 then return string.format("%.1f MB", n / 1e6)
      elseif n >= 1e3 then return string.format("%.0f KB", n / 1e3) end
      return n .. " B"
   end
   local function fill(dirs, files, note)
      store:clear()
      table.sort(dirs); table.sort(files, function(a, b) return a[1] < b[1] end)
      for _, name in ipairs(dirs) do store:append({ [COL.ICON] = "folder", [COL.NAME] = name, [COL.SIZE] = "", [COL.KIND] = "dir" }) end
      for _, f in ipairs(files) do store:append({ [COL.ICON] = "package-x-generic", [COL.NAME] = f[1], [COL.SIZE] = human(f[2]), [COL.KIND] = "file" }) end
      status.label = note or (#files == 0 and "No package files (Name--Version--x86_64.tar.bz2) in this folder." or (#files .. " package file(s) here."))
      ok_btn.sensitive = false
      chosen = nil
   end
   load = function(where)
      where = C.trim(where)
      if where:match("^ftp://") then
         if not where:match("/$") then where = where .. "/" end
         if not valid_ftp(where) then status.label = "That FTP address has characters that are not allowed here." return end
         here = where
         entry.text = here
         store:clear()
         status.label = "Asking the server..."
         C.run({ "curl", "-s", "-S", "--max-time", "25", "--ftp-pasv", here }, nil, function(ok, out)
            if here ~= where then return end
            if not ok then fill({}, {}, "The server did not answer: " .. C.trim(out):gsub("^curl: %(%d+%) ", "")) return end
            local dirs, files = {}, {}
            for line in out:gmatch("[^\r\n]+") do
               local kind, size, name = line:match("^([dl-])%S+%s+%d+%s+%S+%s+%S+%s+(%d+)%s+%S+%s+%S+%s+%S+%s+(.+)$")
               if kind and name ~= "." and name ~= ".." and name:match("^[%w ._+~-]+$") then
                  if kind == "d" then dirs[#dirs + 1] = name
                  elseif kind == "-" and is_package(name) then files[#files + 1] = { name, size } end
               end
            end
            fill(dirs, files)
         end)
         return
      end
      if where == "" then where = here end
      local real = C.trim(C.pread("readlink -f -- " .. C.q(where)))
      if real == "" or C.pread("test -d " .. C.q(real) .. " && echo d") == "" then
         status.label = "No such folder: " .. where
         return
      end
      here = real
      entry.text = here
      local dirs, files = {}, {}
      for name in C.pread("ls -1Ap -- " .. C.q(here)):gmatch("[^\n]+") do
         if name:match("/$") then
            if not name:match("^%.") then dirs[#dirs + 1] = name:sub(1, -2) end
         elseif is_package(name) then
            files[#files + 1] = { name, C.trim(C.pread("stat -c %s -- " .. C.q(here .. "/" .. name))) }
         end
      end
      fill(dirs, files)
   end
   local function up()
      if here:match("^ftp://") then
         local parent = here:match("^(ftp://[^/]+/.-)[^/]+/$")
         if parent then load(parent) end
      elseif here ~= "/" then
         load(here:match("^(.*)/[^/]+$") ~= "" and here:match("^(.*)/[^/]+$") or "/")
      end
   end
   entry.on_activate = function() load(entry.text) end
   local bar = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
   bar:pack_start(C.button("Up", up), false, false, 0)
   bar:pack_start(entry, true, true, 0)
   bar:pack_start(C.button("Go", function() load(entry.text) end), false, false, 0)
   local places = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 6 }
   places:pack_start(C.button("Home", function() load(C.HOME) end), false, false, 0)
   places:pack_start(C.button("Downloads", function() load(C.HOME .. "/Downloads") end), false, false, 0)
   places:pack_start(C.button("USB drives", function() load("/Mount/Media") end), false, false, 0)
   places:pack_start(C.button("FTP server...", function()
      entry.text = "ftp://"
      entry:grab_focus()
      entry:set_position(-1)
      status.label = "Type the server's address, for example ftp://ftp.example.org/pub/ and press Enter. Only public (anonymous) servers; FTP is not encrypted."
   end), false, false, 0)
   box:pack_start(places, false, false, 0)
   box:pack_start(bar, false, false, 0)
   box:pack_start(scroll, true, true, 0)
   box:pack_start(status, false, false, 0)
   d:get_content_area():pack_start(box, true, true, 0)

   view:get_selection().on_changed = function(sel)
      local model, iter = sel:get_selected()
      chosen = iter and model[iter][COL.KIND] == "file" and model[iter][COL.NAME] or nil
      ok_btn.sensitive = chosen ~= nil
   end
   view.on_row_activated = function(_, path)
      local row = store[store:get_iter(path)]
      if row[COL.KIND] == "dir" then
         load(here:match("^ftp://") and (here .. row[COL.NAME] .. "/") or ((here == "/" and "" or here) .. "/" .. row[COL.NAME]))
      else
         chosen = row[COL.NAME]
         d:response(Gtk.ResponseType.OK)
      end
   end
   box:show_all()
   load(here)

   local result
   while true do
      if d:run() ~= Gtk.ResponseType.OK or not chosen then break end
      if not here:match("^ftp://") then result = here .. "/" .. chosen break end
      -- an FTP file: fetch it into Downloads (the dialog stays open and shows the progress)
      local target_dir = C.HOME .. "/Downloads"
      os.execute("mkdir -p " .. C.q(target_dir))
      local target = target_dir .. "/" .. chosen
      status.label = "Downloading " .. chosen .. " ..."
      ok_btn.sensitive = false
      local loop, good, err = GLib.MainLoop(), false, ""
      C.run({ "curl", "-s", "-S", "-f", "--max-time", "1800", "--ftp-pasv", "-o", target .. ".part", here .. chosen }, nil, function(ok, out)
         good, err = ok, out
         loop:quit()
      end)
      loop:run()
      if good and os.rename(target .. ".part", target) then result = target break end
      os.remove(target .. ".part")
      status.label = "The download failed: " .. C.trim(err)
   end
   d:destroy()
   return result
end

function P.build(C)
   local Gtk = C.Gtk
   local admin = C.kind() == "admin"
   local outer, box = C.page("Apps", "Add a program from a GoboLinux package file. The file is checked first: it is installed only when it fits this system.")
   box:pack_start(C.text("A package file is named like  Htop--3.3.0--x86_64.tar.bz2  (GoboLinux's own format, made with CreatePackage). Added programs are kept on the data partition and stay through system updates.", "dim-label"), false, false, 0)

   local scroll, append, clear = C.output_view(170)
   local list_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local busy = false
   local refresh_list

   local WORDS = { OK = "✓ ", WARN = "!  ", FAIL = "✗ " }
   local function show_check(out)
      local name, compatible = nil, false
      for line in out:gmatch("[^\n]+") do
         local tag, rest = line:match("^(%u+) (.*)$")
         if tag == "PACKAGE" then name = rest; append("Package: " .. rest .. "\n")
         elseif tag == "ABOUT" then if rest ~= "" then append("   " .. rest .. "\n") end
         elseif WORDS[tag] then append(WORDS[tag] .. rest .. "\n")
         elseif tag == "RESULT" then
            compatible = rest == "compatible"
            append(compatible and "\nThis package fits this system.\n" or "\nThis package does NOT fit this system. It will not be installed.\n")
         end
      end
      return compatible, name
   end

   local function choose_and_check(then_install)
      if busy then return end
      local file = browse(C)
      if not file then return end
      busy = true
      clear()
      append("Checking " .. file .. " ...\n")
      C.run({ "/System/Index/bin/gobo-app-check", file }, nil, function(_, out)
         busy = false
         local compatible, name = show_check(out)
         if not (compatible and then_install) then return end
         if not C.confirm("Install " .. (name or file) .. "?\nOnly install programs from people you trust: a program can do everything you can do.", "Install") then return end
         busy = true
         append("\nInstalling...\n")
         local last = ""
         C.helper({ "app-install", file }, nil, function(ok, all)
            busy = false
            if ok and all:match("INSTALLED%-OK") then
               append("Installed. It is in the menu and the search now (programs without a menu entry: by their command name).\n")
               C.desktop("pcall(function() require('spin.launcher').refresh() end)")
            else
               append("NOT installed: " .. C.clean_error(last) .. "\n")
            end
            refresh_list()
         end, function(line) last = line end)
      end)
   end

   if admin then
      box:pack_start(C.row(
         C.button("Install an app from a file...", function() choose_and_check(true) end, "suggested-action"),
         C.button("Only check a file...", function() choose_and_check(false) end)), false, false, 0)
   else
      box:pack_start(C.button("Check a package file...", function() choose_and_check(false) end), false, false, 0)
      box:pack_start(C.text("Installing and removing apps needs an administrator's account.", "dim-label"), false, false, 0)
   end
   box:pack_start(scroll, false, false, 0)
   box:pack_start(C.heading("Apps added on this computer"), false, false, 0)
   box:pack_start(list_box, false, false, 0)

   refresh_list = function()
      C.clear(list_box)
      local n = 0
      for line in (C.read(LIST) or ""):gmatch("[^\n]+") do
         local name, version, date, by = line:match("^([^\t]+)\t([^\t]+)\t([^\t]*)\t?(.*)$")
         if name then
            n = n + 1
            local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
            row:pack_start(Gtk.Label { label = name .. " " .. version, xalign = 0, width_chars = 30 }, false, false, 0)
            row:pack_start(C.text("added " .. date .. (by ~= "" and (" by " .. by) or ""), "dim-label"), true, true, 0)
            if admin then
               row:pack_start(C.button("Remove", function()
                  if not C.confirm("Remove " .. name .. " " .. version .. "?\nIts settings in your home folder are kept.", "Remove") then return end
                  C.helper({ "app-remove", name, version }, nil, function(ok, out)
                     if not ok then C.error(C.clean_error(out)) end
                     refresh_list()
                  end)
               end), false, false, 0)
            end
            list_box:pack_start(row, false, false, 0)
         end
      end
      if n == 0 then list_box:pack_start(C.text("None yet.", "dim-label"), false, false, 0) end
      list_box:show_all()
   end
   refresh_list()
   return outer
end

return P
