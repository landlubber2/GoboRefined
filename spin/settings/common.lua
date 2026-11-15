-- Shared helpers of the Settings app (gobo-settings): reading files, running commands, the
-- root helper, dialogs and small layout pieces. Every page gets this table as "C".
local lgi = require("lgi")
local Gtk = lgi.require("Gtk", "3.0")
local GLib, Gio = lgi.GLib, lgi.Gio

local C = {}
C.Gtk, C.GLib, C.Gio = Gtk, GLib, Gio
C.GdkPixbuf = lgi.require("GdkPixbuf", "2.0")

C.HOME = os.getenv("HOME") or ""
C.USER = os.getenv("USER") or ""
C.HELPER = "/System/Index/bin/gobo-settings-helper"
C.ASKPASS = "/System/Index/bin/gobo-askpass"
C.window = nil   -- set by main.lua

-- Files and commands ---------------------------------------------------------------

function C.read(path)
   local f = io.open(path, "r")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

function C.exists(path)
   local f = io.open(path, "r")
   if f then f:close() return true end
   return false
end

function C.q(s)   -- shell quoting
   return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function C.pread(cmd)   -- run a short command, return its output ("" on failure)
   local p = io.popen(cmd .. " 2>/dev/null", "r")
   if not p then return "" end
   local s = p:read("*a") or ""
   p:close()
   return s
end

function C.trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- start a program without waiting (argv table)
function C.spawn(argv)
   local ok, err = pcall(GLib.spawn_async, nil, argv, nil, { "SEARCH_PATH" }, nil)
   if not ok then C.error("Could not start " .. argv[1] .. ":\n" .. tostring(err)) end
end

-- run Lua in the running desktop (Awesome)
function C.desktop(lua_code)
   C.spawn({ "awesome-client", lua_code })
end

-- run argv asynchronously; stdin_text (or nil) is written to its stdin; on_done(ok, output, code)
-- gets stdout and stderr together. on_line(line), if given, gets the output line by line as it
-- comes (stdin is not used then).
function C.run(argv, stdin_text, on_done, on_line)
   local launcher = Gio.SubprocessLauncher.new(on_line and { "STDOUT_PIPE", "STDERR_MERGE" }
      or { "STDIN_PIPE", "STDOUT_PIPE", "STDERR_MERGE" })
   launcher:setenv("SUDO_ASKPASS", C.ASKPASS, true)
   launcher:setenv("LC_ALL", "C", true)
   local proc, err = launcher:spawnv(argv)
   if not proc then
      if on_done then on_done(false, tostring(err), -1) end
      return
   end
   if on_line then
      local stream = Gio.DataInputStream.new(proc:get_stdout_pipe())
      local all = {}
      local function next_line()
         stream:read_line_async(GLib.PRIORITY_DEFAULT, nil, function(s, res)
            local line = s:read_line_finish_utf8(res)
            if line then
               table.insert(all, line)
               on_line(line)
               next_line()
            else
               proc:wait_async(nil, function(p, r)
                  p:wait_finish(r)
                  local code = p:get_if_exited() and p:get_exit_status() or -1
                  if on_done then on_done(code == 0, table.concat(all, "\n"), code) end
               end)
            end
         end)
      end
      next_line()
      return
   end
   proc:communicate_utf8_async(stdin_text, nil, function(p, res)
      -- lgi returns the out-parameters only (stdout; stderr is merged), or nil + error
      local out, err2 = p:communicate_utf8_finish(res)
      local code = p:get_if_exited() and p:get_exit_status() or -1
      if type(out) ~= "string" then out = (out == nil and err2) and tostring(err2) or "" end
      if on_done then on_done(code == 0, out, code) end
   end)
end

-- the root helper: sudo asks the user's password with the graphical prompt (gobo-askpass)
function C.helper(args, stdin_text, on_done, on_line)
   local argv = { "sudo", "-A", C.HELPER }
   for _, a in ipairs(args) do table.insert(argv, a) end
   C.run(argv, stdin_text, on_done, on_line)
end

-- the helper's error text without sudo's noise
function C.clean_error(out)
   out = C.trim(out)
   if out:match("no password was provided") or out:match("a password is required") then
      return "No password was given."
   elseif out:match("incorrect password attempt") then
      return "The password was not correct."
   elseif out:match("is not allowed to execute") or out:match("not in the sudoers") then
      return "This needs an administrator."
   end
   return (out:gsub("gobo%-settings%-helper: ", ""))
end

-- Accounts ------------------------------------------------------------------------

function C.people()   -- { {login, uid, name, admin}, ... } for uid 1000..59999
   local admins = {}
   for line in (C.read("/System/Settings/group") or ""):gmatch("[^\n]+") do
      local name, members = line:match("^([^:]*):[^:]*:[^:]*:(.*)$")
      if name == "sys" then
         for m in members:gmatch("[^,]+") do admins[m] = true end
      end
   end
   local list = {}
   for line in (C.read("/System/Settings/passwd") or ""):gmatch("[^\n]+") do
      local login, uid, gecos = line:match("^([^:]*):[^:]*:(%d+):%d+:([^:]*):")
      uid = tonumber(uid)
      if login and uid >= 1000 and uid < 60000 then
         table.insert(list, { login = login, uid = uid, name = (gecos or ""):match("^([^,]*)") or "",
                              admin = admins[login] == true })
      end
   end
   table.sort(list, function(a, b) return a.uid < b.uid end)
   return list
end

function C.is_admin(login)
   for _, p in ipairs(C.people()) do
      if p.login == (login or C.USER) then return p.admin end
   end
   return false
end

-- Dialogs -------------------------------------------------------------------------

function C.message(text, kind)
   local d = Gtk.MessageDialog {
      transient_for = C.window, modal = true, destroy_with_parent = true, title = "Settings",
      message_type = kind or Gtk.MessageType.INFO, buttons = Gtk.ButtonsType.OK, text = text,
   }
   d:run()
   d:destroy()
end
function C.error(text) C.message(text, Gtk.MessageType.ERROR) end

function C.confirm(text, ok_label, extra_check)   -- returns true / false (and the check's state)
   local d = Gtk.MessageDialog {
      transient_for = C.window, modal = true, destroy_with_parent = true, title = "Settings",
      message_type = Gtk.MessageType.QUESTION, buttons = Gtk.ButtonsType.NONE, text = text,
   }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button(ok_label or "OK", Gtk.ResponseType.OK)
   d:set_default_response(Gtk.ResponseType.CANCEL)
   local check
   if extra_check then
      check = Gtk.CheckButton { label = extra_check }
      d:get_message_area():pack_start(check, false, false, 0)
      check:show()
   end
   local r = d:run()
   local checked = check and check.active
   d:destroy()
   return r == Gtk.ResponseType.OK, checked
end

-- A small form. fields: { {key=, label=, kind="text"|"password"|"check"|"choice", value=, choices={{id,text}}} }
-- validate(values) returns nil or an error text. Returns the values or nil (cancelled).
function C.form(title, fields, ok_label, validate)
   local d = Gtk.Dialog { title = title, transient_for = C.window, modal = true, destroy_with_parent = true }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button(ok_label or "OK", Gtk.ResponseType.OK)
   d:set_default_response(Gtk.ResponseType.OK)
   local grid = Gtk.Grid { row_spacing = 10, column_spacing = 12, margin = 18 }
   local widgets = {}
   for i, f in ipairs(fields) do
      local w
      if f.kind == "check" then
         w = Gtk.CheckButton { label = f.label, active = f.value == true }
         grid:attach(w, 1, i - 1, 1, 1)
      else
         if f.kind == "choice" then
            w = Gtk.ComboBoxText()
            for _, c in ipairs(f.choices) do w:append(c[1], c[2]) end
            w:set_active_id(f.value or f.choices[1][1])
         else
            w = Gtk.Entry { text = f.value or "", activates_default = true, width_chars = 28 }
            if f.kind == "password" then w.visibility = false; w.input_purpose = Gtk.InputPurpose.PASSWORD end
         end
         grid:attach(Gtk.Label { label = f.label, xalign = 1 }, 0, i - 1, 1, 1)
         grid:attach(w, 1, i - 1, 1, 1)
      end
      if f.on_change and f.kind ~= "check" and f.kind ~= "choice" then
         w.on_changed = function() f.on_change(w, widgets) end
      end
      widgets[f.key] = w
   end
   d:get_content_area():pack_start(grid, true, true, 0)
   grid:show_all()
   while true do
      if d:run() ~= Gtk.ResponseType.OK then d:destroy() return nil end
      local values = {}
      for _, f in ipairs(fields) do
         local w = widgets[f.key]
         if f.kind == "check" then values[f.key] = w.active
         elseif f.kind == "choice" then values[f.key] = w:get_active_id()
         else values[f.key] = w.text end
      end
      local problem = validate and validate(values)
      if not problem then
         d:destroy()
         return values
      end
      C.error(problem)
   end
end

function C.check_password(pw, again)
   if pw == "" then return "The password is empty." end
   if #pw > 128 then return "The password is too long." end
   if pw:match("%c") then return "The password may not contain control characters." end
   if pw ~= again then return "The two passwords are not the same." end
end

function C.choose_file(title, filter_name, patterns, folder)
   local d = Gtk.FileChooserDialog { title = title, action = Gtk.FileChooserAction.OPEN, transient_for = C.window, modal = true }
   d:add_button("Cancel", Gtk.ResponseType.CANCEL)
   d:add_button("Open", Gtk.ResponseType.ACCEPT)
   local filter = Gtk.FileFilter()
   filter:set_name(filter_name)
   for _, p in ipairs(patterns) do
      if p:match("/") then filter:add_mime_type(p) else filter:add_pattern(p) end
   end
   d:add_filter(filter)
   if folder and C.exists(folder) then d:set_current_folder(folder) end
   local file
   if d:run() == Gtk.ResponseType.ACCEPT then file = d:get_filename() end
   d:destroy()
   return file
end

-- Layout pieces -------------------------------------------------------------------

-- a page: title on top, then sections; returns the outer widget and the box to add to
function C.page(title, intro)
   local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 14, margin = 28 }
   local t = Gtk.Label { label = title, xalign = 0 }
   t:get_style_context():add_class("gobo-title")
   box:pack_start(t, false, false, 0)
   if intro then box:pack_start(C.text(intro, "dim-label"), false, false, 0) end
   local scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER }
   scroll:add(box)
   return scroll, box
end

function C.heading(text)
   local l = Gtk.Label { label = text, xalign = 0, margin_top = 10 }
   l:get_style_context():add_class("gobo-heading")
   return l
end

function C.text(text, class)
   local l = Gtk.Label { label = text, xalign = 0, wrap = true, max_width_chars = 70 }
   if class then l:get_style_context():add_class(class) end
   return l
end

function C.button(label, on_clicked, class)
   local b = Gtk.Button { label = label, halign = Gtk.Align.START }
   b.on_clicked = function() on_clicked(b) end
   if class then b:get_style_context():add_class(class) end
   return b
end

function C.row(...)   -- widgets side by side
   local box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
   for _, w in ipairs({ ... }) do box:pack_start(w, false, false, 0) end
   return box
end

function C.output_view(height)   -- a read-only monospace text area; returns scroller, append(text), clear()
   local view = Gtk.TextView { editable = false, monospace = true, wrap_mode = Gtk.WrapMode.WORD_CHAR,
                               left_margin = 8, right_margin = 8, top_margin = 6, bottom_margin = 6 }
   local scroll = Gtk.ScrolledWindow { min_content_height = height or 160 }
   scroll:add(view)
   local buffer = view:get_buffer()
   local function append(text)
      buffer:insert(buffer:get_end_iter(), text, -1)
      view:scroll_to_iter(buffer:get_end_iter(), 0, false, 0, 0)
   end
   local function clear() buffer:set_text("", -1) end
   return scroll, append, clear
end

function C.clear(box)
   for _, child in ipairs(box:get_children()) do child:destroy() end
end

-- this computer's IPv4 addresses (not loopback): { {ifname, addr}, ... }
function C.addresses()
   local list = {}
   for line in C.pread("ip -4 -o addr show scope global"):gmatch("[^\n]+") do
      local ifname, addr = line:match("^%d+:%s+(%S+)%s+inet%s+([%d.]+)/")
      if ifname then table.insert(list, { ifname, addr }) end
   end
   return list
end

return C
