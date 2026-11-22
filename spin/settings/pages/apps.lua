-- Software (0.10.8; "Apps" 0.9.2-0.10.7): install programs from a file and remove them, in one place.
-- Installing is done by gobo-install-app (the same dialog as the file manager's right click >
-- Install): AppImages, GoboLinux packages (Name--Version--x86_64.tar.bz2, checked by gobo-app-check,
-- installed system-wide by gobo-settings-helper app-install) and archives of a ready program. The
-- file comes from a file chooser, or from a folder or an FTP server (anonymous) through the package
-- browser of 0.9.2. The list shows everything installed by any of these ways: programs for everyone
-- (apps.list: packages and, since 0.10.8, AppImages/folders copied to /Programs; removed with
-- gobo-settings-helper app-remove, administrators) and the current user's own programs in
-- ~/Applications (removed without a password: the folder, its start menu entries and its pins).
local P = { id = "apps", title = "Software", icon = "system-software-install" }

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
   local Gtk, GLib, Gio = C.Gtk, C.GLib, C.Gio
   local admin = C.kind() == "admin"
   local APPS_HOME = C.HOME .. "/Applications"
   local USER_APPS = GLib.get_user_data_dir() .. "/applications"
   local outer, box = C.page("Software", "Install a program from a file: an AppImage, a GoboLinux package or an archive (.tar.gz, .zip ...) holding a ready program. The file manager does the same: right click on the file > Install.")
   box:pack_start(C.text("Programs \"only for me\" go to your folder ~/Applications (no password). Programs \"for everyone\" and GoboLinux packages go to /Programs (an administrator's password). Both stay through system updates.", "dim-label"), false, false, 0)

   local status = C.text("", "dim-label")
   local system_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local user_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local refresh_list

   local function install(file)
      if not file then return end
      status.label = "The installer is open for " .. (file:match("([^/]+)$") or file) .. " ..."
      C.run({ "/System/Index/bin/gobo-install-app", file }, nil, function()
         status.label = ""
         refresh_list()
      end)
   end
   box:pack_start(C.row(
      C.button("Install a program from a file...", function()
         install(C.choose_file("Choose a program file", "Program files (AppImage, package, archive)",
            { "*.AppImage", "*.appimage", "*.tar.gz", "*.tgz", "*.tar.xz", "*.txz", "*.tar.bz2", "*.tbz2", "*.tar.zst", "*.zip", "*.7z" },
            C.exists(C.HOME .. "/Downloads") and (C.HOME .. "/Downloads") or C.HOME))
      end, "suggested-action"),
      C.button("GoboLinux package from a folder or FTP...", function() install(browse(C)) end)), false, false, 0)
   box:pack_start(status, false, false, 0)
   if not admin then
      box:pack_start(C.text("GoboLinux packages and programs for everyone need an administrator's account; your own programs do not.", "dim-label"), false, false, 0)
   end
   box:pack_start(C.heading("For everyone on this computer"), false, false, 0)
   box:pack_start(system_box, false, false, 0)
   box:pack_start(C.heading("Only for you"), false, false, 0)
   box:pack_start(user_box, false, false, 0)

   local KIND_WORDS = { appimage = "AppImage", folder = "program folder", package = "GoboLinux package" }
   local function row_of(name, detail, on_remove)
      local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
      row:pack_start(Gtk.Label { label = name, xalign = 0, width_chars = 30, ellipsize = "END" }, false, false, 0)
      row:pack_start(C.text(detail, "dim-label"), true, true, 0)
      if on_remove then row:pack_start(C.button("Remove", on_remove), false, false, 0) end
      return row
   end

   -- one per-user program: its folder, its start menu entries and its pins
   local function remove_own(folder, name)
      local dir_name = folder:sub(#APPS_HOME + 2)
      if folder:sub(1, #APPS_HOME + 1) ~= APPS_HOME .. "/" or dir_name == "" or dir_name:find("/") or dir_name:match("^%.") then return end
      local info = Gio.File.new_for_path(folder):query_info("standard::type,standard::is-symlink", Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, nil)
      if not info or info:get_file_type() ~= "DIRECTORY" or info:get_is_symlink() then return end
      if not C.confirm("Remove " .. name .. "?\nThe folder ~/Applications/" .. dir_name .. " is deleted with everything in it. The program's settings in your home folder are kept.", "Remove") then return end
      local ids = {}
      for f in C.pread("grep -l -s -F -x -e " .. C.q("X-GoboRefined-AppImage=" .. folder) .. " -- " .. C.q(USER_APPS) .. "/*.desktop"):gmatch("[^\n]+") do
         ids[f:match("([^/]+)$")] = true
         os.remove(f)
      end
      os.execute("rm -rf --one-file-system -- " .. C.q(folder))
      for _, list in ipairs({ C.HOME .. "/.config/goborefined/start-pins", C.HOME .. "/.config/goborefined/taskbar-pins" }) do
         local text = C.read(list)
         if text then
            local out, changed = {}, false
            for line in text:gmatch("[^\n]+") do
               local id = line:match("^app\t(.+)$")
               if id and ids[id] then changed = true else table.insert(out, line) end
            end
            if changed then
               local f = io.open(list .. ".new", "w")
               if f then f:write(table.concat(out, "\n") .. "\n"); f:close(); os.rename(list .. ".new", list) end
            end
         end
      end
      C.desktop("if spin_menu_reload then spin_menu_reload() end; if spin_start_pins_reload then spin_start_pins_reload() end; "
         .. "if spin_taskbar_pins_refresh then spin_taskbar_pins_refresh() end")
      refresh_list()
   end

   refresh_list = function()
      C.clear(system_box)
      C.clear(user_box)
      local n = 0
      for line in (C.read(LIST) or ""):gmatch("[^\n]+") do
         local f = {}
         for field in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(f, field) end
         local name, version, date, by, kind = f[1], f[2], f[3] or "", f[4] or "", f[5] or ""
         if name and version and name ~= "" then
            n = n + 1
            local title = name .. " " .. version
            if kind ~= "" then   -- copied to /Programs by gobo-install-app: show its own name
               local desk = C.trim(C.pread("grep -h -m1 '^Name=' /Programs/" .. C.q(name) .. "/" .. C.q(version) .. "/share/applications/*.desktop"))
               if desk ~= "" then title = desk:sub(6) .. " " .. version end
            end
            system_box:pack_start(row_of(title, (KIND_WORDS[kind ~= "" and kind or "package"] or kind) .. ", added " .. date .. (by ~= "" and (" by " .. by) or ""),
               admin and function()
                  if not C.confirm("Remove " .. title .. " for everyone?\nSettings in the home folders are kept.", "Remove") then return end
                  C.helper({ "app-remove", name, version }, nil, function(ok, out)
                     if not ok then C.error(C.clean_error(out)) end
                     C.desktop("if spin_menu_reload then spin_menu_reload() end; pcall(function() require('spin.launcher').refresh() end)")
                     refresh_list()
                  end)
               end or nil), false, false, 0)
         end
      end
      if n == 0 then system_box:pack_start(C.text("None yet.", "dim-label"), false, false, 0) end
      local m = 0
      for dir in C.pread("ls -1 -- " .. C.q(APPS_HOME)):gmatch("[^\n]+") do
         local folder = APPS_HOME .. "/" .. dir
         local manifest = C.read(folder .. "/.goborefined-app")
         local name, version, kind
         if manifest then
            name = manifest:match("\nname=([^\n]*)") or dir
            version = manifest:match("\nversion=([^\n]*)") or ""
            kind = manifest:match("\nkind=([^\n]*)") or "folder"
         elseif C.pread("ls -1 -- " .. C.q(folder) .. " | grep -i '\\.appimage$'") ~= "" then
            name, version, kind = dir, "", "appimage"   -- installed by 0.10.6 / 0.10.7
         end
         if name then
            m = m + 1
            local size = C.trim(C.pread("du -sh -- " .. C.q(folder) .. " | cut -f 1"))
            user_box:pack_start(row_of(name .. (version ~= "" and (" " .. version) or ""),
               (KIND_WORDS[kind] or kind) .. (size ~= "" and (", " .. size) or "") .. ", in ~/Applications/" .. dir,
               function() remove_own(folder, name) end), false, false, 0)
         end
      end
      if m == 0 then user_box:pack_start(C.text("None yet.", "dim-label"), false, false, 0) end
      system_box:show_all()
      user_box:show_all()
   end
   refresh_list()
   return outer
end

return P
