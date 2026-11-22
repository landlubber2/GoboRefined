-- GoboRefined 0.10.8: ONE installer for every kind of program file (gobo-install-app FILE). Started by
-- the file manager (right click "Install"; a double click on an AppImage, a GoboLinux package or a
-- program archive asks "Install or just run once?" through gobo-install-app --ask) and by Settings >
-- Software ("Install a program from a file..."). Replaces the AppImage-only installer of 0.10.6.
--
-- The kinds (app-detect.lua, by content): AppImage, GoboLinux package, plain archive of a ready
-- program (one top folder with an executable, e.g. an Electron app). Anything else is refused with
-- what the file is. The same dialog for all three: icon, name, version, where it goes and who gets
-- it, "Add to start menu" (on, with the category), "Pin to taskbar" (off), the trust warning,
-- Install / Cancel, progress, result with "Open now".
--
-- Who gets it (owner's answer 2026-11-22):
--   * AppImages and program archives: "Only for me" (default; ~/Applications/<Name>/, no password,
--     untouched by system updates) or "For everyone on this computer" (administrators; the program
--     goes where GoboLinux packages added in Settings go: /Programs/<Name>/<Version>/ on the
--     machine's own layer, kept through updates and rollbacks; gobo-settings-helper
--     app-install-folder, administrator password). When the password is not given, is wrong three
--     times (sudo's limit) or the system-wide install fails, the program is installed "Only for me"
--     instead, with a one-line notice.
--   * GoboLinux packages: always for everyone (/Programs), administrators only (gobo-app-check,
--     then gobo-settings-helper app-install, as Settings > Apps did since 0.9.2).
--
-- Plain archives are unpacked by gobo-archive (no absolute paths, no "..", no device files, no
-- links pointing outside, size against free space; set-ID bits removed) into a private folder
-- ~/Applications/.gobo-install-XXXXXX first, so the dialog can show the real name, version and icon
-- (a .desktop file inside, resources/app/package.json or app.asar's package.json; icons from
-- .desktop files, resources/app/**/icon*.png, PNGs next to the program, app.asar). Cancel removes
-- that folder. Executable bits are left as the archive had them (the chosen program gets one).
-- Electron's chrome-sandbox is never made set-user-ID: this kernel lets programs use user
-- namespaces, which Electron's sandbox uses instead.
--
-- Per-user installs: ~/Applications/<Name>/ with a small description .goborefined-app (name, version,
-- kind, exec, desktop id) that Settings > Software lists and removes; the start menu entry
-- ~/.local/share/applications/appimage-<slug>.desktop (AppImages, as in 0.10.6) or
-- goborefined-<slug>.desktop (folders), with X-GoboRefined-AppImage=<folder> (the start menu editor
-- offers to delete the folder) and NoDisplay=true when it is not wanted in the menu (it still
-- exists for the taskbar pin and Software). Taskbar pins: spin.startpanel.taskbar_pin().
package.path = "/System/Aliens/LuaRocks/share/lua/5.3/?.lua;/System/Aliens/LuaRocks/share/lua/5.3/?/init.lua;" .. package.path
package.cpath = "/System/Aliens/LuaRocks/lib/lua/5.3/?.so;" .. package.cpath
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path

local lgi = require("lgi")
lgi.GLib.set_prgname("gobo-install-app")
lgi.GLib.set_application_name("Install a program")
local Gtk = lgi.require("Gtk", "3.0")
local GLib, Gio = lgi.GLib, lgi.Gio
local GdkPixbuf = lgi.require("GdkPixbuf", "2.0")
local C = require("common")
local D = require("app-detect")
local AM = require("appimage-meta")

local TITLE = "Install a program"
local APPS_HOME = C.HOME .. "/Applications"
local USER_DIR = GLib.get_user_data_dir() .. "/applications"
local ARCHIVE_GUI = "/System/Index/bin/gobo-archive-gui"
local MANIFEST = ".goborefined-app"
local TRUST = "Only install programs from people you trust: a program can do everything you can do."

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
      window_position = Gtk.WindowPosition.CENTER, buttons = Gtk.ButtonsType.OK, text = text, secondary_text = secondary }
   d:run()
   d:destroy()
end
local function fail(text, secondary)
   say(text, secondary, Gtk.MessageType.ERROR)
   os.exit(1)
end
local function ask(text, secondary, buttons)   -- buttons: { {label, id}, ... } last = default
   local d = Gtk.MessageDialog { modal = true, title = TITLE, message_type = Gtk.MessageType.QUESTION,
      window_position = Gtk.WindowPosition.CENTER, buttons = Gtk.ButtonsType.NONE, text = text, secondary_text = secondary }
   for i, b in ipairs(buttons) do d:add_button(b[1], i) end
   d:set_default_response(#buttons)
   local r = d:run()
   d:destroy()
   while Gtk.events_pending() do Gtk.main_iteration() end
   return buttons[r] and buttons[r][2] or nil
end
local function sh(cmd) return os.execute(cmd .. " > /dev/null 2>&1") == true end
local function short(path)
   if path:sub(1, #C.HOME + 1) == C.HOME .. "/" then return "~" .. path:sub(#C.HOME + 1) end
   return path
end
local function clean(s)
   s = tostring(s or ""):gsub("[%c\"$`\\%%]", ""):gsub("/", "-"):gsub("^[%s.]+", ""):gsub("%s+$", "")
   if #s > 60 then s = s:sub(1, 60):gsub("[\128-\255]+$", ""):gsub("%s+$", "") end
   return s
end
local function slug_of(name)
   local s = name:lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
   return s ~= "" and s or "app"
end
-- /Programs names: "Google Chrome" -> "GoogleChrome"; versions: GoboLinux's characters only
local function program_name(name)
   local n = ""
   for w in name:gmatch("[%w+_.-]+") do n = n .. w:sub(1, 1):upper() .. w:sub(2) end
   n = n:gsub("^[^%w]+", "")
   if #n > 60 then n = n:sub(1, 60) end
   return n ~= "" and n or "App"
end
local function program_version(v)
   v = tostring(v or ""):gsub("[^%w+_.~-]", "")
   if not v:match("^[%w]") or #v > 40 then v = os.date("%Y.%m.%d") end
   return v
end
local function is_dir(path)
   local info = Gio.File.new_for_path(path):query_info("standard::type,standard::is-symlink", Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, nil)
   return info and info:get_file_type() == "DIRECTORY" and not info:get_is_symlink()
end
local function exists(path) return Gio.File.new_for_path(path):query_exists(nil) end

-- run argv, keep the window alive, return ok, output
local function run_wait(argv, stdin_text)
   local loop, ok, out = GLib.MainLoop(), false, ""
   C.run(argv, stdin_text, function(good, text) ok, out = good, text or ""; loop:quit() end)
   loop:run()
   return ok, out
end

-- a small "please wait" window while something slow runs (fn is called with it shown)
local function busy(text, fn)
   local w = Gtk.Window { title = TITLE, default_width = 360, resizable = false, window_position = Gtk.WindowPosition.CENTER,
                          icon_name = "system-software-install", deletable = false }
   local b = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12, margin = 20 }
   local sp = Gtk.Spinner { active = true }
   b:pack_start(sp, false, false, 0)
   b:pack_start(Gtk.Label { label = text, xalign = 0, wrap = true, max_width_chars = 44 }, true, true, 0)
   w:add(b)
   w:show_all()
   for _ = 1, 20 do if Gtk.events_pending() then Gtk.main_iteration() end end
   local r = { fn() }
   w:destroy()
   while Gtk.events_pending() do Gtk.main_iteration() end
   return table.unpack(r)
end

-- arguments ---------------------------------------------------------------------------------
local mode = "install"
local src = arg[1] or ""
if src == "--ask" then mode = "ask"; src = arg[2] or "" end
if src == "" then
   io.stderr:write("usage: gobo-install-app [--ask] FILE\n")
   os.exit(2)
end
if src:sub(1, 1) ~= "/" then src = GLib.get_current_dir() .. "/" .. src end
local src_name = src:match("([^/]+)$") or ""
local kind_of_account = C.kind()
if kind_of_account == "simple" then fail("Programs cannot be installed in this account.") end
local admin = kind_of_account == "admin"
do
   local info = Gio.File.new_for_path(src):query_info("standard::type", Gio.FileQueryInfoFlags.NONE, nil)
   if not info or info:get_file_type() ~= "REGULAR" then fail("The file was not found.", src) end
end
if src:sub(1, #APPS_HOME + 1) == APPS_HOME .. "/" then
   if mode == "ask" then   -- a double click on an installed AppImage: just start it
      GLib.spawn_async(src:match("^(.*)/"), { src }, nil, {}, nil)
      os.exit(0)
   end
   fail("This program is already installed.", "It is in " .. short(src) .. ".")
end

local info = busy("Looking at " .. src_name .. " ...", function() return D.detect(src) end)
local kind = info.kind

local function not_a_program(what)
   fail("This is not a program file GoboRefined can install.",
      src_name .. " is " .. what .. ".\n\nPrograms can be installed from AppImages (.AppImage), GoboLinux packages "
      .. "(Name--Version--x86_64.tar.bz2) and archives (.tar.gz, .tar.xz, .zip ...) holding a ready program folder.")
end

-- the double click: "Install or just run once?" -------------------------------------------
if mode == "ask" then
   if kind == "appimage" then
      local r = ask("Install " .. src_name .. "?",
         "Installing puts it in its own folder in ~/Applications and in the start menu, so it stays. "
         .. "Or run it just once from where it is now.\n\n" .. TRUST,
         { { "Cancel", "cancel" }, { "Run once", "run" }, { "Install...", "install" } })
      if r == "run" then
         sh("chmod u+x -- " .. C.q(src))
         local ok, err = pcall(GLib.spawn_async, src:match("^(.*)/"), { src }, nil, {}, nil)
         if not ok then fail("The program could not be started.", tostring(err)) end
         os.exit(0)
      elseif r ~= "install" then os.exit(0) end
   elseif kind == "package" or kind == "archive" then
      local what = kind == "package" and ("a GoboLinux package of " .. info.name .. " " .. info.version)
         or "an archive holding a program"
      local r = ask("Install " .. src_name .. "?", "This is " .. what .. ". Install it, or only unpack the files here?\n\n" .. TRUST,
         { { "Cancel", "cancel" }, { "Extract here", "extract" }, { "Install...", "install" } })
      if r == "extract" then
         GLib.spawn_async(nil, { ARCHIVE_GUI, "--here", src }, nil, { "SEARCH_PATH" }, nil)
         os.exit(0)
      elseif r ~= "install" then os.exit(0) end
   elseif kind == "files" or kind == "windows" then
      -- an ordinary archive: the archive tool's own question
      GLib.spawn_async(nil, { ARCHIVE_GUI, "--open", src }, nil, { "SEARCH_PATH" }, nil)
      os.exit(0)
   else
      not_a_program(D.describe(src))
   end
end

if kind == "files" then
   fail("This archive does not hold a program.",
      src_name .. " holds " .. info.files .. " file(s) but nothing that can be started. Use \"Extract here\" in the file manager to unpack it.")
elseif kind == "windows" then
   fail("This is a Windows program.", src_name .. " holds Windows programs (.exe). GoboRefined runs Linux programs only.")
elseif kind ~= "appimage" and kind ~= "package" and kind ~= "archive" then
   not_a_program(info.elf and "a Linux program file (not an AppImage); start it from a terminal or put it in a folder"
      or D.describe(src))
end
if kind == "package" and not admin then
   fail("Installing a GoboLinux package needs an administrator.",
      "GoboLinux packages are installed for everyone on this computer (in /Programs). Ask an administrator to install " .. src_name .. ".")
end

-- reading the program ----------------------------------------------------------------------
local P = { kind = kind, categories = {} }   -- name, version, icon (file), exec (relative), ...
local stage, payload                        -- archives / everyone: the private folder and the program in it
local function new_stage()
   GLib.mkdir_with_parents(APPS_HOME, tonumber("0755", 8))
   local s = C.trim(C.pread("mktemp -d " .. C.q(APPS_HOME .. "/.gobo-install-XXXXXX")))
   if s == "" or not is_dir(s) then fail("No working folder could be made in " .. short(APPS_HOME) .. ".") end
   return s
end
local function drop_stage()
   if stage and stage:match("/Applications/%.gobo%-install%-[%w]+$") and is_dir(stage) then
      sh("rm -rf --one-file-system -- " .. C.q(stage))
   end
   stage = nil
end

local meta
if kind == "appimage" then
   meta = busy("Reading " .. src_name .. " ...", function() return AM.read(src) or {} end)
   P.name = clean(meta.name)
   if P.name == "" then P.name = clean(D.simplify(src_name)) end
   P.version = (meta.version and meta.version ~= "" and meta.version) or D.version_in(src_name) or ""
   P.comment, P.wmclass, P.categories = meta.comment, meta.wmclass, meta.categories or {}
   P.icon = meta.icon_file
   P.what = "AppImage"
elseif kind == "package" then
   P.name, P.version, P.what = info.name, info.version, "GoboLinux package"
   local ok, out = busy("Checking " .. src_name .. " ...", function() return run_wait({ "/System/Index/bin/gobo-app-check", src }) end)
   P.check_lines, P.compatible = {}, false
   for line in out:gmatch("[^\n]+") do
      local tag, rest = line:match("^(%u+) (.*)$")
      if tag == "ABOUT" and rest ~= "" then P.comment = rest
      elseif tag == "OK" or tag == "WARN" or tag == "FAIL" then
         table.insert(P.check_lines, ({ OK = "✓ ", WARN = "!  ", FAIL = "✗ " })[tag] .. rest)
      elseif tag == "RESULT" then P.compatible = rest == "compatible" and ok
      elseif tag == "PACKAGE" then
         local n, v = rest:match("^(%S+) (%S+)")
         if n then P.name, P.version = n, v end
      end
   end
else   -- a program archive: unpack it first (the dialog shows what is really in it)
   stage = new_stage()
   local ok, out = busy("Unpacking " .. src_name .. " ...", function()
      return run_wait({ D.ARCHIVE, "extract", src, stage .. "/app" })
   end)
   if not ok then
      drop_stage()
      fail("The archive could not be unpacked.", C.trim(out):gsub("gobo%-archive: ", ""))
   end
   payload = stage .. "/app"
   -- one top folder: the program is that folder
   local only, count = nil, 0
   local en = Gio.File.new_for_path(payload):enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, nil)
   if en then
      while true do
         local i = en:next_file(nil)
         if not i then break end
         count = count + 1
         only = i:get_name()
      end
      en:close(nil)
   end
   local root = (count == 1 and is_dir(payload .. "/" .. only)) and (payload .. "/" .. only) or payload
   P.root = root
   P.what = "Program folder (archive)"
   -- programs: the listing's candidates that are really programs (ELF or a script)
   P.candidates = {}
   for _, c in ipairs(info.candidates or {}) do
      local f = root .. "/" .. c.rel
      local h = D.head(f, 4) or ""
      if h:sub(1, 4) == "\127ELF" or h:sub(1, 2) == "#!" then
         c.elf = h:sub(1, 4) == "\127ELF"
         table.insert(P.candidates, c)
      end
   end
   table.sort(P.candidates, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      if a.elf ~= b.elf then return a.elf end
      return a.size > b.size
   end)
   if #P.candidates == 0 then
      drop_stage()
      fail("This archive does not hold a program that can be started.", src_name)
   end
   -- name, version: a .desktop inside, package.json (Electron), the folder's name
   local base = (count == 1 and only) or D.simplify(src_name:gsub("%.tar%.%w+$", ""):gsub("%.%w+$", ""))
   P.name = clean(D.simplify(base))
   P.version = D.version_in(base) or D.version_in(src_name) or ""
   local desk = C.trim(C.pread("find " .. C.q(root) .. " -maxdepth 3 -name '*.desktop' -type f | head -n 1"))
   if desk ~= "" then
      local kf = GLib.KeyFile()
      if kf:load_from_file(desk, GLib.KeyFileFlags.NONE) and kf:has_group("Desktop Entry") then
         local n = clean(kf:get_string("Desktop Entry", "Name"))
         if n ~= "" then P.name = n end
         P.comment = kf:get_string("Desktop Entry", "Comment")
         P.categories = kf:get_string_list("Desktop Entry", "Categories") or {}
         P.wmclass = kf:get_string("Desktop Entry", "StartupWMClass")
         local ic = kf:get_string("Desktop Entry", "Icon")
         if ic and not ic:find("..", 1, true) then
            local cand = ic:sub(1, 1) == "/" and nil or C.trim(C.pread("find " .. C.q(root) .. " -maxdepth 6 \\( -name "
               .. C.q(ic) .. " -o -name " .. C.q(ic .. ".png") .. " -o -name " .. C.q(ic .. ".svg") .. " \\) -type f | head -n 1"))
            if cand and cand ~= "" then P.icon = cand end
         end
      end
   end
   local asar = root .. "/resources/app.asar"
   local pkg = C.read(root .. "/resources/app/package.json")
   if pkg then
      local pn = pkg:match('"productName"%s*:%s*"([^"]+)"')
      local pv = pkg:match('"version"%s*:%s*"([^"]+)"')
      if pn and clean(pn) ~= "" then P.name = clean(pn) end
      if pv then P.version = pv end
   elseif exists(asar) then
      local out2 = C.pread("python3 -I " .. C.q(here .. "/asar-file.py") .. " " .. C.q(asar) .. " --package")
      local pn, pv = out2:match("^([^\t]*)\t([^\n]*)")
      if pn and clean(pn) ~= "" then P.name = clean(pn) end
      if pv and pv ~= "" then P.version = pv end
   end
   if not P.icon then
      -- PNG/SVG files in the folder, best first: icon*/logo*/<program name>*, under resources/app or
      -- */linux/ or share/icons, next to the program; the bigger file wins among equals
      local best, best_score = nil, -1
      local exe_base = (P.candidates[1].rel:match("([^/]+)$") or ""):lower()
      local list = C.pread("find " .. C.q(root) .. " -maxdepth 7 \\( -iname '*.png' -o -iname '*.svg' \\) -type f -size -4M -printf '%s\\t%P\\n' | head -n 3000")
      for line in list:gmatch("[^\n]+") do
         local size, rel = line:match("^(%d+)\t(.+)$")
         if rel and not rel:lower():find("node_modules", 1, true) then
            local low = rel:lower()
            local file = low:match("([^/]+)$")
            local score = 0
            if file:match("^icon") or file:match("^logo") then score = score + 50 end
            if exe_base ~= "" and file:sub(1, #exe_base) == exe_base then score = score + 40 end
            if low:match("^resources/app/") or low:match("/linux/") or low:match("share/icons") or low:match("share/pixmaps") then score = score + 20 end
            if not rel:find("/", 1, true) then score = score + 15 end
            if file:match("tray") or file:match("template") or file:match("small") then score = score - 40 end
            if score > 0 then
               score = score * 10000000 + math.min(tonumber(size), 9999999)
               if score > best_score then best, best_score = root .. "/" .. rel, score end
            end
         end
      end
      P.icon = best
   end
   if not P.icon and exists(asar) then
      local out3 = stage .. "/icon-from-asar.png"
      if sh("python3 -I " .. C.q(here .. "/asar-file.py") .. " " .. C.q(asar) .. " --icon " .. C.q(out3)) then P.icon = out3 end
   end
   if P.name == "" then P.name = "Program" end
end
if P.name == "" then P.name = "App" end
P.version = clean(P.version)
P.slug = slug_of(P.name)

-- the dialog --------------------------------------------------------------------------------
local own_cat
for _, c in ipairs(P.categories or {}) do
   if IS_MAIN[c] then own_cat = c break end
end
local win = Gtk.Window { title = (kind == "package" and "Install " or "Install ") .. P.name, default_width = 500, resizable = false,
                         window_position = Gtk.WindowPosition.CENTER, icon_name = "system-software-install" }
local result = { done = false }
win.on_destroy = function() Gtk.main_quit() end
local outer = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 14, margin = 18 }
win:add(outer)

local function icon_widget(path, size)
   if path and path:sub(1, 1) == "/" then
      local ok, pb = pcall(GdkPixbuf.Pixbuf.new_from_file_at_size, path, size, size)
      if ok and pb then return Gtk.Image.new_from_pixbuf(pb) end
   end
   return Gtk.Image { icon_name = kind == "package" and "package-x-generic" or "application-x-executable", pixel_size = size }
end
do
   local head = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 14 }
   head:pack_start(icon_widget(P.icon, 48), false, false, 0)
   local t = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 3, valign = Gtk.Align.CENTER }
   t:pack_start(Gtk.Label { use_markup = true, xalign = 0, ellipsize = "END",
      label = "<b>" .. GLib.markup_escape_text(P.name, -1) .. "</b>" }, false, false, 0)
   local sub = Gtk.Label { xalign = 0, ellipsize = "END",
      label = (P.version ~= "" and ("Version " .. P.version) or "Version not known") .. "  ·  " .. P.what }
   sub:get_style_context():add_class("dim-label")
   t:pack_start(sub, false, false, 0)
   local file = Gtk.Label { label = short(src), xalign = 0, ellipsize = "MIDDLE", max_width_chars = 52 }
   file:get_style_context():add_class("dim-label")
   t:pack_start(file, false, false, 0)
   head:pack_start(t, true, true, 0)
   outer:pack_start(head, false, false, 0)
end

local stack = Gtk.Stack { transition_type = Gtk.StackTransitionType.CROSSFADE }
outer:pack_start(stack, true, true, 0)

-- page "form"
local form = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 10 }
local me_radio, all_radio
local where = Gtk.Label { xalign = 0, wrap = true, max_width_chars = 60 }
where:get_style_context():add_class("dim-label")
local function update_where()
   if kind == "package" then
      where.label = "GoboLinux packages are installed for everyone on this computer, in /Programs/" .. P.name
         .. ". It stays through system updates. You will be asked for your password."
   elseif all_radio.active then
      where.label = "It goes to /Programs/" .. program_name(P.name) .. " for every account on this computer and stays through "
         .. "system updates. You will be asked for your password."
   else
      where.label = "It goes to " .. short(APPS_HOME .. "/" .. P.name) .. ", only for you, without a password. System updates leave it alone."
   end
end
if kind == "package" then
   form:pack_start(Gtk.Label { label = "<b>Who gets it:</b> everyone on this computer", use_markup = true, xalign = 0 }, false, false, 0)
else
   local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 16 }
   row:pack_start(Gtk.Label { label = "<b>Who gets it:</b>", use_markup = true, xalign = 0 }, false, false, 0)
   me_radio = Gtk.RadioButton { label = "Only for me" }
   all_radio = Gtk.RadioButton { label = "For everyone on this computer", group = me_radio }
   me_radio.active = true
   if not admin then
      all_radio.sensitive = false
      all_radio.tooltip_text = "Needs an administrator's account"
   end
   me_radio.on_toggled = update_where
   row:pack_start(me_radio, false, false, 0)
   row:pack_start(all_radio, false, false, 0)
   form:pack_start(row, false, false, 0)
end
form:pack_start(where, false, false, 0)

local exe_combo
if kind == "archive" and #P.candidates > 1 and P.candidates[1].score < 70 then
   local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
   row:pack_start(Gtk.Label { label = "Program to start:", xalign = 0 }, false, false, 0)
   exe_combo = Gtk.ComboBoxText()
   for i, c in ipairs(P.candidates) do
      if i > 8 then break end
      exe_combo:append(tostring(i), c.rel)
   end
   exe_combo:set_active_id("1")
   row:pack_start(exe_combo, true, true, 0)
   form:pack_start(row, false, false, 0)
end

local menu_check = Gtk.CheckButton { label = kind == "package" and "Add to start menu (its own entries)" or "Add to start menu, under", active = true }
local combo = Gtk.ComboBoxText()
for _, c in ipairs(CATS) do combo:append(c[1], c[2]) end
combo:set_active_id(own_cat or "Utility")
do
   local row = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
   row:pack_start(menu_check, false, false, 0)
   if kind ~= "package" then
      row:pack_start(combo, false, false, 0)
      menu_check.on_toggled = function() combo.sensitive = menu_check.active end
   else
      menu_check.sensitive = false   -- a package's own .desktop files always go to the start menu
   end
   form:pack_start(row, false, false, 0)
end
local pin_check = Gtk.CheckButton { label = "Pin to taskbar", active = false }
form:pack_start(pin_check, false, false, 0)

if kind == "package" then
   local tv = Gtk.TextView { editable = false, cursor_visible = false, monospace = true, wrap_mode = Gtk.WrapMode.WORD_CHAR }
   tv.buffer.text = table.concat(P.check_lines, "\n") .. "\n\n" .. (P.compatible and "This package fits this system."
      or "This package does NOT fit this system. It cannot be installed.")
   local sc = Gtk.ScrolledWindow { min_content_height = 110 }
   sc:add(tv)
   local ex = Gtk.Expander { label = P.compatible and "Check: it fits this system (details)" or "Check: it does NOT fit this system (details)",
                             expanded = not P.compatible }
   ex:add(sc)
   form:pack_start(ex, false, false, 0)
end
local trust = Gtk.Label { label = TRUST, xalign = 0, wrap = true, max_width_chars = 60 }
trust:get_style_context():add_class("dim-label")
form:pack_start(trust, false, false, 0)
stack:add_named(form, "form")

-- page "busy"
local busy_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 10, valign = Gtk.Align.CENTER }
local progress = Gtk.ProgressBar { pulse_step = 0.08 }
local busy_label = Gtk.Label { label = "Installing ...", xalign = 0, ellipsize = "END" }
busy_box:pack_start(busy_label, false, false, 0)
busy_box:pack_start(progress, false, false, 0)
stack:add_named(busy_box, "busy")

-- page "done"
local done_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 8, valign = Gtk.Align.CENTER }
local done_label = Gtk.Label { xalign = 0, wrap = true, max_width_chars = 60, use_markup = true }
local done_note = Gtk.Label { xalign = 0, wrap = true, max_width_chars = 60 }
done_note:get_style_context():add_class("dim-label")
done_box:pack_start(done_label, false, false, 0)
done_box:pack_start(done_note, false, false, 0)
stack:add_named(done_box, "done")

local buttons = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8, halign = Gtk.Align.END }
local cancel_btn = Gtk.Button { label = "Cancel" }
local install_btn = Gtk.Button { label = "Install", can_default = true }
install_btn:get_style_context():add_class("suggested-action")
local open_btn = Gtk.Button { label = "Open now", no_show_all = true }
open_btn:get_style_context():add_class("suggested-action")
local close_btn = Gtk.Button { label = "Close", no_show_all = true }
buttons:pack_start(cancel_btn, false, false, 0)
buttons:pack_start(install_btn, false, false, 0)
buttons:pack_start(close_btn, false, false, 0)
buttons:pack_start(open_btn, false, false, 0)
outer:pack_start(buttons, false, false, 0)
if kind == "package" and not P.compatible then install_btn.sensitive = false end
update_where()

-- installing ----------------------------------------------------------------------------------
local pulse_id
local function show_busy(text)
   busy_label.label = text
   stack.visible_child_name = "busy"
   cancel_btn.sensitive, install_btn.sensitive = false, false
   pulse_id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, function() progress:pulse() return true end)
end
local function desktop_reload(pin_id)
   local code = "if spin_menu_reload then spin_menu_reload() end; pcall(function() require('spin.launcher').refresh() end)"
   if pin_id then
      code = code .. "; pcall(function() require('spin.startpanel').taskbar_pin('app', '" .. pin_id .. "') end)"
   end
   run_wait({ "awesome-client", code })
end
local open_target   -- a .desktop file to start with "Open now"
local function show_done(text, note)
   if pulse_id then GLib.source_remove(pulse_id); pulse_id = nil end
   done_label.label = text
   done_note.label = note or ""
   done_note.visible = (note or "") ~= ""
   stack.visible_child_name = "done"
   cancel_btn:hide(); install_btn:hide()
   close_btn:show()
   if open_target then open_btn:show(); open_btn:grab_focus() else close_btn:grab_focus() end
end
local function show_failed(text, note)
   open_target = nil
   show_done("<b>" .. GLib.markup_escape_text(text, -1) .. "</b>", note)
end

local function exec_rel()
   if kind == "appimage" then return nil end
   local c = P.candidates[1]
   if exe_combo then c = P.candidates[tonumber(exe_combo:get_active_id()) or 1] or c end
   local root_rel = P.root:sub(#payload + 2)
   return (root_rel ~= "" and (root_rel .. "/") or "") .. c.rel
end

local function write_desktop(path, lines)
   GLib.mkdir_with_parents(path:match("^(.*)/"), tonumber("0755", 8))
   local f = io.open(path .. ".new", "w")
   if not f then return false end
   f:write(table.concat(lines, "\n") .. "\n")
   f:close()
   return os.rename(path .. ".new", path)
end

-- "Only for me": ~/Applications/<Name>/
local function install_for_me()
   local folder = APPS_HOME .. "/" .. P.name
   local in_menu, cat = menu_check.active, combo:get_active_id()
   local desktop_id = (kind == "appimage" and "appimage-" or "goborefined-") .. P.slug .. ".desktop"
   local desktop_path = USER_DIR .. "/" .. desktop_id
   local exec_path, icon
   if kind == "appimage" then
      local file_name = clean(src_name)
      if file_name ~= src_name or file_name == "" then file_name = P.name .. ".AppImage" end
      local dest = folder .. "/" .. file_name
      local old = {}
      if is_dir(folder) then
         for n in C.pread("ls -1A -- " .. C.q(folder)):gmatch("[^\n]+") do
            if n:lower():match("%.appimage$") then table.insert(old, n) end
         end
      elseif exists(folder) then return false, short(folder) .. " exists and is not a folder." end
      if #old > 0 and ask("\"" .. P.name .. "\" is already installed for you.", "Replace " .. table.concat(old, ", ") .. " with " .. src_name .. "?",
            { { "Cancel", "cancel" }, { "Replace", "replace" } }) ~= "replace" then
         return nil
      end
      GLib.mkdir_with_parents(folder, tonumber("0755", 8))
      local from = (payload and exists(payload .. "/" .. file_name)) and (payload .. "/" .. file_name) or src
      if not sh("mv -f -- " .. C.q(from) .. " " .. C.q(dest)) then return false, "The AppImage could not be moved to " .. short(folder) .. "." end
      sh("chmod 755 -- " .. C.q(dest))
      for _, f in ipairs(old) do if f ~= file_name then os.remove(folder .. "/" .. f) end end
      icon = AM.copy_icon(meta, folder)
      exec_path = dest
   else
      local rel = exec_rel()
      if exists(folder) or is_dir(folder) then
         if not is_dir(folder) then return false, short(folder) .. " exists and is not a folder." end
         if ask("\"" .. P.name .. "\" is already installed for you.", "Replace the folder " .. short(folder) .. " with the new one? Everything in it is deleted.",
               { { "Cancel", "cancel" }, { "Replace", "replace" } }) ~= "replace" then
            return nil
         end
         if not sh("rm -rf --one-file-system -- " .. C.q(folder)) then return false, "The old folder could not be removed." end
      end
      local root_rel = P.root:sub(#payload + 2)
      local program_root = P.root
      if not sh("mv -T -- " .. C.q(program_root) .. " " .. C.q(folder)) then return false, "The program could not be moved to " .. short(folder) .. "." end
      if root_rel ~= "" then rel = rel:sub(#root_rel + 2) end
      exec_path = folder .. "/" .. rel
      sh("chmod u+x,go+rx -- " .. C.q(exec_path))
      if P.icon then
         local ic = P.icon
         if ic:sub(1, #program_root + 1) == program_root .. "/" then ic = folder .. ic:sub(#program_root + 1) end
         local ext = ic:lower():match("%.svg$") and "svg" or "png"
         if exists(ic) and sh("cp -- " .. C.q(ic) .. " " .. C.q(folder .. "/.goborefined-icon." .. ext)) then
            icon = folder .. "/.goborefined-icon." .. ext
         end
      end
   end
   icon = icon or "application-x-executable"
   local lines = { "[Desktop Entry]", "Type=Application", "Name=" .. P.name,
      "Exec=\"" .. exec_path .. "\" %U", "Icon=" .. icon, "Terminal=false",
      "Categories=" .. (in_menu and (cat .. ";") or "") }
   if kind ~= "appimage" then table.insert(lines, "Path=" .. folder) end
   if not in_menu then table.insert(lines, "NoDisplay=true") end
   if clean(P.comment) ~= "" then table.insert(lines, "Comment=" .. clean(P.comment)) end
   if clean(P.wmclass) ~= "" then table.insert(lines, "StartupWMClass=" .. clean(P.wmclass)) end
   table.insert(lines, "X-GoboRefined-Menu=edited")
   table.insert(lines, "X-GoboRefined-AppImage=" .. folder)
   table.insert(lines, "X-GoboRefined-Icon=checked")
   if not write_desktop(desktop_path, lines) then return false, "The start menu entry could not be written." end
   local mf = io.open(folder .. "/" .. MANIFEST, "w")
   if mf then
      mf:write("# GoboRefined: installed with gobo-install-app (Settings > Software lists and removes it)\n",
         "name=", P.name, "\nversion=", P.version, "\nkind=", kind == "appimage" and "appimage" or "folder",
         "\nexec=", exec_path, "\ndesktop=", desktop_id, "\nfrom=", src_name, "\ninstalled=", os.date("%Y-%m-%d"), "\n")
      mf:close()
   end
   drop_stage()
   return true, desktop_path, desktop_id
end

-- "For everyone": the program in the private folder, then gobo-settings-helper app-install-folder
local function install_for_everyone(on_done)
   if not stage then stage = new_stage() end
   payload = payload or (stage .. "/app")
   local rel
   if kind == "appimage" then
      GLib.mkdir_with_parents(payload, tonumber("0755", 8))
      local file_name = clean(src_name)
      if file_name ~= src_name or file_name == "" then file_name = P.name .. ".AppImage" end
      if not sh("mv -f -- " .. C.q(src) .. " " .. C.q(payload .. "/" .. file_name)) then return on_done(false, "the AppImage could not be moved") end
      sh("chmod 755 -- " .. C.q(payload .. "/" .. file_name))
      rel = file_name
      local ic = AM.copy_icon(meta, payload)
      P.icon = ic
   else
      rel = exec_rel()
   end
   local icon_rel = ""
   if P.icon and P.icon:sub(1, #payload + 1) == payload .. "/" then icon_rel = P.icon:sub(#payload + 2)
   elseif P.icon and exists(P.icon) then
      local ext = P.icon:lower():match("%.svg$") and "svg" or "png"
      if sh("cp -- " .. C.q(P.icon) .. " " .. C.q(payload .. "/.goborefined-icon." .. ext)) then icon_rel = ".goborefined-icon." .. ext end
   end
   local meta_lines = {
      "kind=" .. (kind == "appimage" and "appimage" or "folder"),
      "exec=" .. rel, "icon=" .. icon_rel, "title=" .. P.name,
      "comment=" .. clean(P.comment), "wmclass=" .. clean(P.wmclass),
      "categories=" .. (menu_check.active and (combo:get_active_id() .. ";") or ""),
      "menu=" .. (menu_check.active and "yes" or "no"),
   }
   C.helper({ "app-install-folder", stage, program_name(P.name), program_version(P.version) }, table.concat(meta_lines, "\n") .. "\n",
      function(ok, out)
         local id = out:match("INSTALLED%-OK %S+ %S+ (%S+)")
         if ok and id then
            drop_stage()
            on_done(true, "/System/Index/share/applications/" .. id, id)
         else
            local tail = ""
            for line in out:gmatch("[^\n]+") do if C.trim(line) ~= "" then tail = line end end
            on_done(false, C.clean_error(tail ~= "" and tail or out))
         end
      end)
end

local function finish_ok(desktop_path, desktop_id, who)
   open_target = desktop_path
   desktop_reload(pin_check.active and desktop_id or nil)
   show_done("<b>" .. GLib.markup_escape_text(P.name, -1) .. "</b> is installed " .. who .. ".",
      (menu_check.active and "It is in the start menu" or "It is not in the start menu (Settings > Software lists it)")
      .. (pin_check.active and " and pinned to the taskbar." or ".") .. (result.notice and ("\n" .. result.notice) or ""))
end

install_btn.on_clicked = function()
   if kind == "package" then
      show_busy("Installing " .. P.name .. " " .. P.version .. " ... (you will be asked for your password)")
      local last = ""
      C.helper({ "app-install", src }, nil, function(ok, all)
         local n, v = all:match("INSTALLED%-OK (%S+) (%S+)")
         if ok and n then
            local id = C.trim(C.pread("ls -1 /Programs/" .. C.q(n) .. "/" .. C.q(v) .. "/share/applications/ 2>/dev/null | grep '\\.desktop$' | head -n 1"))
            if id ~= "" and exists("/System/Index/share/applications/" .. id) then
               finish_ok("/System/Index/share/applications/" .. id, id, "for everyone on this computer")
            else
               open_target = nil
               desktop_reload(nil)
               show_done("<b>" .. GLib.markup_escape_text(P.name, -1) .. "</b> is installed for everyone on this computer.",
                  "It has no start menu entry: start it by its command name in a terminal.")
            end
         else
            show_failed("It was not installed.", C.clean_error(last ~= "" and last or all))
         end
      end, function(line) last = line; busy_label.label = line end)
      return
   end
   if all_radio and all_radio.active then
      show_busy("Installing " .. P.name .. " for everyone ... (you will be asked for your password)")
      install_for_everyone(function(ok, a, b)
         if ok then return finish_ok(a, b, "for everyone on this computer") end
         -- owner's rule: no password, a wrong one three times, or a failure: only for me instead
         result.notice = "Installed only for you: " .. (a or "the system-wide install did not work")
         busy_label.label = "Installing " .. P.name .. " for you ..."
         local ok2, p2, id2 = install_for_me()
         if ok2 then finish_ok(p2, id2, "for you") else show_failed("It was not installed.", p2 or "Cancelled.") end
      end)
      return
   end
   show_busy("Installing " .. P.name .. " ...")
   local ok, p, id = install_for_me()
   if ok then finish_ok(p, id, "for you")
   elseif ok == nil then   -- the replace question was answered with Cancel
      if pulse_id then GLib.source_remove(pulse_id); pulse_id = nil end
      stack.visible_child_name = "form"
      cancel_btn.sensitive, install_btn.sensitive = true, true
   else show_failed("It was not installed.", p) end
end
cancel_btn.on_clicked = function() win:destroy() end
close_btn.on_clicked = function() win:destroy() end
open_btn.on_clicked = function()
   if open_target then
      local appinfo = Gio.DesktopAppInfo.new_from_filename(open_target)
      if appinfo then pcall(function() appinfo:launch({}, nil) end) end
   end
   win:destroy()
end

win:show_all()
done_note.visible = false
install_btn:grab_focus()
Gtk.main()
drop_stage()
