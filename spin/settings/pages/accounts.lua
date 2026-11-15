-- Accounts: own password, the people on this computer (add, remove, administrator or
-- standard, set a password), automatic login.
--
-- Administrator = member of group "sys" (sudoers: "%sys ALL=(ALL) ALL"; the installer puts the
-- first user there). Standard = everyone else: no sudo, but may change their own password
-- (sudoers allows exactly "gobo-settings-helper own-password" for %users, with their password).
-- Every change goes through gobo-settings-helper (sudo asks the password of the person at the
-- computer; passwords go to the helper on stdin).
local P = { id = "accounts", title = "Accounts", icon = "system-users" }

function P.build(C)
   local Gtk = C.Gtk
   local outer, box = C.page("Accounts")
   local me = C.USER

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

   local function password_form(title, intro)
      return C.form(title, {
         { key = "pw", label = "New password", kind = "password" },
         { key = "again", label = "Repeat it", kind = "password" },
      }, "Change", function(v) return C.check_password(v.pw, v.again) end)
   end

   -- Your account
   box:pack_start(C.heading("Your account"), false, false, 0)
   local my_admin = C.is_admin(me)
   box:pack_start(C.text(string.format("%s (%s), %s", me, (function()
      for _, p in ipairs(C.people()) do if p.login == me then return p.name ~= "" and p.name or me end end
      return me end)(), my_admin and "administrator" or "standard account")), false, false, 0)
   box:pack_start(C.button("Change my password...", function()
      local v = password_form("Change my password")
      if not v then return end
      C.message("Next, type your CURRENT password in the box that opens.")
      C.helper({ "own-password" }, v.pw .. "\n", function(ok, out)
         done_msg(ok, out, "Your password has been changed.")
      end)
   end), false, false, 0)

   -- People
   box:pack_start(C.heading("People on this computer"), false, false, 0)
   if not my_admin then
      box:pack_start(C.text("Only an administrator can add or change other accounts.", "dim-label"), false, false, 0)
   end
   box:pack_start(list_box, false, false, 0)

   fill = function()
      C.clear(list_box)
      local people = C.people()
      local admins = 0
      for _, p in ipairs(people) do if p.admin then admins = admins + 1 end end
      for _, p in ipairs(people) do
         local line = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 8 }
         local label = Gtk.Label { xalign = 0, width_chars = 34, ellipsize = 3,
            label = string.format("%s (%s)%s", p.name ~= "" and p.name or p.login, p.login, p.login == me and " - you" or "") }
         line:pack_start(label, false, false, 0)
         line:pack_start(Gtk.Label { label = p.admin and "Administrator" or "Standard", xalign = 0, width_chars = 14 }, false, false, 0)
         if my_admin then
            local role = C.button(p.admin and "Make standard" or "Make administrator", function()
               C.helper({ "set-admin", p.login, p.admin and "no" or "yes" }, nil, function(ok, out)
                  done_msg(ok, out, nil, fill)
               end)
            end)
            role.sensitive = not (p.login == me or (p.admin and admins <= 1))
            local pw = C.button("Set password...", function()
               local v = password_form("New password for " .. p.login)
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
            line:pack_start(role, false, false, 0)
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
            { key = "full", label = "Full name", on_change = function(w, ws)
                 local login = w.text:lower():gsub("[^a-z0-9]", ""):sub(1, 16)
                 if ws.login.text == "" or ws.login.text == suggested then ws.login.text = login; suggested = login end
              end },
            { key = "login", label = "Login name" },
            { key = "pw", label = "Password", kind = "password" },
            { key = "again", label = "Repeat it", kind = "password" },
            { key = "admin", label = "Administrator (may change the system and install updates)", kind = "check" },
         }, "Add", function(v)
            if v.full:match("[%c:,=\\]") or #v.full > 64 then return "The full name may not contain : , = \\ (and at most 64 characters)." end
            if not v.login:match("^[a-z_][a-z0-9_-]*$") or #v.login > 31 then
               return "The login name: small letters a-z, digits, _ and -, starting with a letter, at most 31 characters."
            end
            for _, p in ipairs(C.people()) do if p.login == v.login then return "This login name is already used." end end
            if C.pread("grep -c " .. C.q("^" .. v.login .. ":") .. " /System/Settings/passwd"):match("^[1-9]") then
               return "This login name is already used by the system."
            end
            return C.check_password(v.pw, v.again)
         end)
         if not v then return end
         C.helper({ "add-user", v.login, v.admin and "admin" or "standard" }, v.full .. "\n" .. v.pw .. "\n", function(ok, out)
            done_msg(ok, out, v.login .. " can now log in at the login screen.", fill)
         end)
      end), false, false, 0)

      box:pack_start(C.heading("Automatic login"), false, false, 0)
      box:pack_start(C.text("With automatic login, the computer starts the desktop of one person without asking for a password.", "dim-label"), false, false, 0)
      box:pack_start(C.button("Automatic login...", function()
         C.helper({ "autologin-status" }, nil, function(ok, out)
            if not ok then C.error(C.clean_error(out)) return end
            local current = C.trim(out):match("([^\n]*)$")
            local choices = { { "off", "Off (always ask for the password)" } }
            for _, p in ipairs(C.people()) do table.insert(choices, { p.login, "Log in " .. p.login .. " automatically" }) end
            local v = C.form("Automatic login", { { key = "who", label = "At start", kind = "choice", value = current, choices = choices } }, "Save")
            if not v or v.who == current then return end
            C.helper({ "autologin", v.who }, nil, function(ok2, out2)
               done_msg(ok2, out2, v.who == "off" and "Automatic login is off." or (v.who .. " will be logged in automatically at start."))
            end)
         end)
      end), false, false, 0)
   end
   return outer
end

return P
