-- Accounts: own password, the people on this computer (add, remove, kind of account, set a
-- password, the programs of a Simple account), automatic login.
--
-- 0.9.1: three kinds. Administrator = member of group "sys" (sudoers: "%sys ALL=(ALL) ALL"; the
-- installer puts the first user there). Standard = no sudo, no system settings. Simple = group
-- "simple": a short list of programs (chosen here), the file manager shows only the home folder
-- and USB drives; for a child, a grandparent, a guest. Everyone may change their own password
-- (sudoers allows exactly "gobo-settings-helper own-password" for %users, with their password).
-- Every change goes through gobo-settings-helper (sudo asks the password of the person at the
-- computer; passwords go to the helper on stdin).
local P = { id = "accounts", title = "Accounts", icon = "system-users" }

local APPS_DIR = "/System/Index/share/applications"
local DEFAULT_APPS = "/Programs/GoboSpin/Current/share/gobo-settings/simple-apps.default"
local USER_APPS = "/Data/Variable/lib/gobo-settings/simple-apps/"

-- installed programs with a menu entry: { {id, name}, ... } sorted by name
local function installed_apps(C)
   local list = {}
   for id in C.pread("ls -1 " .. APPS_DIR):gmatch("[^\n]+") do
      if id:match("^[%w][%w._+-]*%.desktop$") then
         local text = C.read(APPS_DIR .. "/" .. id) or ""
         local entry = text:match("%[Desktop Entry%]\n(.-)\n%[") or text:match("%[Desktop Entry%]\n(.*)$") or ""
         local name = entry:match("\nName=([^\n]+)") or entry:match("^Name=([^\n]+)")
         local hidden = entry:match("\nNoDisplay=true") or entry:match("\nHidden=true")
         local app_type = entry:match("\nType=([^\n]+)") or entry:match("^Type=([^\n]+)")
         if name and not hidden and (app_type == nil or app_type == "Application") then
            table.insert(list, { id = id, name = name })
         end
      end
   end
   table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
   return list
end

local function read_ids(C, path)
   local text = C.read(path)
   if not text then return nil end
   local set = {}
   for line in text:gmatch("[^\n]+") do
      line = C.trim(line)
      if line ~= "" and not line:match("^#") then set[line] = true end
   end
   return set
end

function P.build(C)
   local Gtk = C.Gtk
   local outer, box = C.page("Accounts")
   local me = C.USER
   local my_kind = C.kind(me)
   local my_admin = my_kind == "admin"

   local function done_msg(ok, out, success_text, after)
      if ok then
         if success_text then C.message(success_text) end
      else
         C.error(C.clean_error(out))
      end
      if after then after() end
   end

   local list_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local fill   -- refills the list

   local function password_form(title, kind)
      local min = C.PW_MIN[kind] or 8
      return C.form(title, {
         { key = "note", kind = "note", label = string.format("At least %d characters.", min) },
         { key = "pw", label = "New password", kind = "password" },
         { key = "again", label = "Repeat it", kind = "password" },
      }, "Change", function(v) return C.check_password(v.pw, v.again, kind) end)
   end

   -- Your account
   box:pack_start(C.heading("Your account"), false, false, 0)
   local my_name = me
   for _, p in ipairs(C.people()) do if p.login == me and p.name ~= "" then my_name = p.name end end
   box:pack_start(C.text(string.format("%s (%s), %s account", my_name, me, C.KIND_NAMES[my_kind]:lower())), false, false, 0)
   box:pack_start(C.button("Change my password...", function()
      local v = password_form("Change my password", my_kind)
      if not v then return end
      C.message("Next, type your CURRENT password in the box that opens.")
      C.helper({ "own-password" }, v.pw .. "\n", function(ok, out)
         done_msg(ok, out, "Your password has been changed.")
      end)
   end), false, false, 0)

   if my_kind == "simple" then return outer end

   -- People
   box:pack_start(C.heading("People on this computer"), false, false, 0)
   if not my_admin then
      box:pack_start(C.text("Only an administrator can add or change other accounts.", "dim-label"), false, false, 0)
   end
   box:pack_start(list_box, false, false, 0)

   -- the programs of a Simple account
   local function choose_programs(p)
      local current = read_ids(C, USER_APPS .. p.login) or read_ids(C, DEFAULT_APPS) or {}
      local d = Gtk.Dialog { title = "Programs of " .. p.login, transient_for = C.window, modal = true,
                             destroy_with_parent = true, default_height = 520 }
      d:add_button("Cancel", Gtk.ResponseType.CANCEL)
      d:add_button("Save", Gtk.ResponseType.OK)
      local vbox = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 8, margin = 16 }
      vbox:pack_start(C.text(string.format("%s sees only the ticked programs in the menu, the search and the taskbar " ..
         "(from the next login). Settings is always there, with their own pages only. Leave out the terminal " ..
         "and system tools.", p.login), "dim-label"), false, false, 0)
      local inner = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 2 }
      local checks = {}
      for _, app in ipairs(installed_apps(C)) do
         if app.id ~= "gobo-settings.desktop" then
            local c = Gtk.CheckButton { label = app.name, active = current[app.id] == true }
            checks[app.id] = c
            inner:pack_start(c, false, false, 0)
         end
      end
      local scroll = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER, min_content_height = 360 }
      scroll:add(inner)
      vbox:pack_start(scroll, true, true, 0)
      d:get_content_area():pack_start(vbox, true, true, 0)
      vbox:show_all()
      local r = d:run()
      local chosen = {}
      for id, c in pairs(checks) do if c.active then table.insert(chosen, id) end end
      d:destroy()
      if r ~= Gtk.ResponseType.OK then return end
      table.sort(chosen)
      C.helper({ "simple-apps", p.login }, table.concat(chosen, "\n") .. "\n", function(ok, out)
         done_msg(ok, out, string.format("Saved. %s sees these programs from the next login.", p.login))
      end)
   end

   -- 0.10.2: which internal disks (and, for a Simple account, USB drives) a person may open.
   -- The list comes from "gobo-settings-helper boot-disks" (written at every start).
   local DISKS_LIST = "/Data/Variable/run/gobo-disks.list"
   local function read_disks()
      local list = {}
      for line in (C.read(DISKS_LIST) or ""):gmatch("[^\n]+") do
         local f = {}
         for v in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(f, v) end
         if f[1] and f[1]:match("^%x%x%x%x%x%x$") and f[2] == "gobo-disk-" .. f[1] then
            table.insert(list, { id = f[1], group = f[2], name = f[3] or "?", fstype = f[4] or "",
                                 size = tonumber(f[5]) or 0, state = f[6] or "", dev = f[7] or "" })
         end
      end
      return list
   end
   local FS_NAMES = { ntfs = "Windows (NTFS)", vfat = "FAT", exfat = "exFAT", ext2 = "Linux (ext2)",
                      ext3 = "Linux (ext3)", ext4 = "Linux (ext4)", btrfs = "Linux (btrfs)", xfs = "Linux (XFS)" }
   local function choose_disks(p)
      local disks = read_disks()
      local d = Gtk.Dialog { title = "Disks of " .. p.login, transient_for = C.window, modal = true,
                             destroy_with_parent = true }
      d:add_button("Cancel", Gtk.ResponseType.CANCEL)
      d:add_button("Save", Gtk.ResponseType.OK)
      local vbox = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 8, margin = 16 }
      local function note(text)
         local l = C.text(text, "dim-label")
         l.max_width_chars = 70
         vbox:pack_start(l, false, false, 0)
      end
      note(string.format("Which disks of this computer %s may open (in the file manager: /Mount/Disks). " ..
         "A change applies from the next login of %s.", p.login, p.login))
      local checks, usb = {}, nil
      if #disks == 0 then
         vbox:pack_start(C.text("This computer has no other disks or partitions (besides GoboRefined's own)."), false, false, 0)
      end
      local members = {}
      for _, dk in ipairs(disks) do
         members = C.group_members(dk.group)
         local label = string.format("%s  (%s, %.1f GB)%s", dk.name, FS_NAMES[dk.fstype] or dk.fstype, dk.size / 1e9,
            dk.state == "ro" and " - read-only: Windows did not shut down fully" or
            (dk.state == "unmounted" and " - could not be opened" or ""))
         local c = Gtk.CheckButton { label = label, active = p.admin or members[p.login] == true }
         if p.admin then c.sensitive = false end
         checks[dk.id] = c
         vbox:pack_start(c, false, false, 0)
      end
      if p.admin and #disks > 0 then
         note("Administrators can always open every disk.")
      end
      if p.kind == "simple" then
         vbox:pack_start(C.heading("USB sticks and external drives"), false, false, 0)
         usb = Gtk.CheckButton { label = "May use USB sticks and external drives",
                                 active = C.group_members("gobo-usb")[p.login] == true }
         vbox:pack_start(usb, false, false, 0)
      end
      if #disks > 0 then
         note("Only a whole disk partition can be allowed or not: hiding just the Windows user folders " ..
            "(C:\\Users) while showing the rest is not reliable, because a partition is opened the same way " ..
            "for everyone. Windows usually keeps the users' files on C: and other data often on D:, so " ..
            "allowing D: but not C: is the usual choice. A Windows disk shows as read-only after Windows " ..
            "was hibernated or started with Fast Startup: shut Windows down with Shift + Shut down.")
      end
      d:get_content_area():pack_start(vbox, true, true, 0)
      vbox:show_all()
      local r = d:run()
      local lines = {}
      if r == Gtk.ResponseType.OK then
         for _, dk in ipairs(disks) do
            local want = checks[dk.id].active
            local had = C.group_members(dk.group)[p.login] == true
            if not p.admin and want ~= had then
               table.insert(lines, dk.id .. (want and " on" or " off"))
            end
         end
         if usb and usb.active ~= (C.group_members("gobo-usb")[p.login] == true) then
            table.insert(lines, usb.active and "usb on" or "usb off")
         end
      end
      d:destroy()
      if r ~= Gtk.ResponseType.OK or #lines == 0 then return end
      C.helper({ "disk-access", p.login }, table.concat(lines, "\n") .. "\n", function(ok, out)
         done_msg(ok, out, string.format("Saved. This applies from the next login of %s.", p.login))
      end)
   end

   local function kind_choices()
      return { { "admin", "Administrator" }, { "standard", "Standard" }, { "simple", "Simple" } }
   end

   fill = function()
      C.clear(list_box)
      local people = C.people()
      local admins = 0
      for _, p in ipairs(people) do if p.admin then admins = admins + 1 end end
      for _, p in ipairs(people) do
         local line = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
         local label = Gtk.Label { xalign = 0, width_chars = 30, ellipsize = 3,
            label = string.format("%s (%s)%s", p.name ~= "" and p.name or p.login, p.login, p.login == me and " - you" or "") }
         line:pack_start(label, false, false, 0)
         line:pack_start(Gtk.Label { label = C.KIND_NAMES[p.kind], xalign = 0, width_chars = 13 }, false, false, 0)
         if my_admin then
            local kind_b = C.button("Kind...", function()
               local v = C.form("Kind of account: " .. p.login, {
                  { key = "kind", label = "Kind", kind = "choice", value = p.kind, choices = kind_choices(),
                    on_change = function(w, ws) ws.help.label = C.KIND_HELP[w:get_active_id()] or "" end },
                  { key = "help", kind = "note", label = C.KIND_HELP[p.kind] },
                  { key = "note2", kind = "note", label = "The change applies from their next login." },
               }, "Change")
               if not v or v.kind == p.kind then return end
               C.helper({ "set-kind", p.login, v.kind }, nil, function(ok, out)
                  done_msg(ok, out, string.format("%s is now a %s account (from the next login).", p.login,
                     C.KIND_NAMES[v.kind]:lower()), fill)
               end)
            end)
            kind_b.sensitive = not (p.login == me or (p.admin and admins <= 1))
            local pw = C.button("Set password...", function()
               local v = password_form("New password for " .. p.login, p.kind)
               if not v then return end
               C.helper({ "set-password", p.login }, v.pw .. "\n", function(ok, out)
                  done_msg(ok, out, "The password of " .. p.login .. " has been changed.")
               end)
            end)
            pw.sensitive = p.login ~= me
            local rm = C.button("Remove...", function()
               local yes, del = C.confirm(string.format("Remove the account of %s (%s)?\nThey will no longer be able to log in.",
                  p.name ~= "" and p.name or p.login, p.login), "Remove " .. p.login,
                  "Also delete the home folder /Users/" .. p.login .. " and every file in it")
               if not yes then return end
               C.helper({ "remove-user", p.login, del and "delete-home" or "keep-home" }, nil, function(ok, out)
                  done_msg(ok, out, "The account of " .. p.login .. " has been removed." ..
                     (del and "" or "\nThe home folder /Users/" .. p.login .. " was kept."), fill)
               end)
            end, "destructive-action")
            rm.sensitive = not (p.login == me or (p.admin and admins <= 1))
            line:pack_start(kind_b, false, false, 0)
            if p.kind == "simple" then
               line:pack_start(C.button("Programs...", function() choose_programs(p) end), false, false, 0)
            end
            line:pack_start(C.button("Disks...", function() choose_disks(p) end), false, false, 0)
            line:pack_start(pw, false, false, 0)
            line:pack_start(rm, false, false, 0)
         end
         list_box:pack_start(line, false, false, 0)
      end
      list_box:show_all()
   end
   fill()

   if my_admin then
      box:pack_start(C.button("Add a person...", function()
         local suggested
         local v = C.form("Add a person", {
            { key = "kind", label = "Kind of account", kind = "choice", value = "standard", choices = kind_choices(),
              on_change = function(w, ws)
                 local k = w:get_active_id()
                 ws.help.label = C.KIND_HELP[k] or ""
                 ws.large.sensitive = k == "simple"
                 ws.pwnote.label = string.format("Password: at least %d characters.", C.PW_MIN[k] or 8)
              end },
            { key = "help", kind = "note", label = C.KIND_HELP.standard },
            { key = "full", label = "Full name", on_change = function(w, ws)
                 local login = w.text:lower():gsub("[^a-z0-9]", ""):sub(1, 16)
                 if ws.login.text == "" or ws.login.text == suggested then ws.login.text = login; suggested = login end
              end },
            { key = "login", label = "Login name" },
            { key = "pwnote", kind = "note", label = "Password: at least 8 characters." },
            { key = "pw", label = "Password", kind = "password" },
            { key = "again", label = "Repeat it", kind = "password" },
            { key = "large", label = "Larger text and icons (Simple accounts)", kind = "check" },
         }, "Add", function(v)
            if v.full:match("[%c:,=\\]") or #v.full > 64 then return "The full name may not contain : , = \\ (and at most 64 characters)." end
            if not v.login:match("^[a-z_][a-z0-9_-]*$") or #v.login > 31 then
               return "The login name: small letters a-z, digits, _ and -, starting with a letter, at most 31 characters."
            end
            for _, p in ipairs(C.people()) do if p.login == v.login then return "This login name is already used." end end
            if C.pread("grep -c " .. C.q("^" .. v.login .. ":") .. " /System/Settings/passwd"):match("^[1-9]") then
               return "This login name is already used by the system."
            end
            return C.check_password(v.pw, v.again, v.kind)
         end)
         if not v then return end
         local args = { "add-user", v.login, v.kind }
         if v.kind == "simple" and v.large then table.insert(args, "large-text") end
         C.helper(args, v.full .. "\n" .. v.pw .. "\n", function(ok, out)
            done_msg(ok, out, v.login .. " can now log in at the login screen." ..
               (v.kind == "simple" and "\nTheir programs: the button Programs... next to their name." or ""), fill)
         end)
      end), false, false, 0)

      box:pack_start(C.heading("Automatic login"), false, false, 0)
      box:pack_start(C.text("With automatic login, the computer starts the desktop of one person without asking for a password. " ..
         "Anyone who switches the computer on gets into that account.", "dim-label"), false, false, 0)
      box:pack_start(C.button("Automatic login...", function()
         C.helper({ "autologin-status" }, nil, function(ok, out)
            if not ok then C.error(C.clean_error(out)) return end
            local current = C.trim(out):match("([^\n]*)$")
            local choices = { { "off", "Off (always ask for the password)" } }
            local kinds = {}
            for _, p in ipairs(C.people()) do
               kinds[p.login] = p.kind
               table.insert(choices, { p.login, "Log in " .. p.login .. " automatically" })
            end
            local v = C.form("Automatic login", { { key = "who", label = "At start", kind = "choice", value = current, choices = choices } }, "Save")
            if not v or v.who == current then return end
            local args = { "autologin", v.who }
            if v.who ~= "off" then
               -- 0.9.1: a plain warning; an administrator's account needs an explicit yes
               local text = string.format("Anyone who starts this computer will be logged in as %s, without a password, " ..
                  "and can use everything in that account.", v.who)
               if kinds[v.who] == "admin" then
                  local yes, sure = C.confirm(text .. "\n\n" .. v.who .. " is an ADMINISTRATOR: that person could also change " ..
                     "the system, install updates and change other accounts.", "Log in automatically",
                     "I understand: anyone at this computer gets administrator rights")
                  if not yes then return end
                  if not sure then C.error("Tick the box to confirm, or choose another account.") return end
                  table.insert(args, "confirmed")
               elseif not C.confirm(text, "Log in automatically") then
                  return
               end
            end
            C.helper(args, nil, function(ok2, out2)
               done_msg(ok2, out2, v.who == "off" and "Automatic login is off." or (v.who .. " will be logged in automatically at start."))
            end)
         end)
      end), false, false, 0)
   end
   return outer
end

return P
