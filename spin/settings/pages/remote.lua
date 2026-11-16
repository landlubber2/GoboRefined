-- Remote access: the SSH server on or off (off by default). On = sshd now and at every start
-- (flag /Data/Variable/lib/gobo-settings/ssh-enabled on the data partition; the boot scripts run
-- "gobo-settings-helper boot-ssh"). Root never logs in over SSH (sshd is started with
-- PermitRootLogin=no); people log in with their own password and use sudo.
local P = { id = "remote", title = "Remote access", icon = "network-server" }

local FLAG = "/Data/Variable/lib/gobo-settings/ssh-enabled"
local PIDFILE = "/Data/Variable/run/gobo-sshd.pid"

function P.build(C)
   local Gtk = C.Gtk
   local outer, box = C.page("Remote access",
      "Lets you log in to this computer from another computer on the same network, with a terminal (SSH).")

   local function running()
      local pid = C.trim(C.read(PIDFILE) or "")
      return pid:match("^%d+$") and C.exists("/proc/" .. pid .. "/status")
   end

   local sw = Gtk.Switch { active = C.exists(FLAG), valign = Gtk.Align.CENTER }
   local state = C.text("")
   local how = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local setting = false

   local function refresh()
      setting = true
      sw.active = C.exists(FLAG)
      sw.state = sw.active
      setting = false
      local on = C.exists(FLAG)
      state.label = on and (running() and "On: this computer accepts SSH logins (also after a restart)."
                                       or "On, but the SSH server is not running (try switching off and on).")
                       or "Off (nobody can log in from another computer)."
      C.clear(how)
      if on then
         local addrs = C.addresses()
         if #addrs == 0 then
            how:pack_start(C.text("This computer has no network address right now."), false, false, 0)
         else
            how:pack_start(C.text("On the other computer, type one of these in a terminal (then your password):"), false, false, 0)
            for _, a in ipairs(addrs) do
               how:pack_start(C.text(string.format("ssh %s@%s        (%s)", C.USER, a[2], a[1]), "gobo-value"), false, false, 0)
            end
         end
         how:pack_start(C.text("The administrator account root cannot log in over SSH: log in as a person, then use sudo.", "dim-label"), false, false, 0)
      end
      how:show_all()
   end

   sw.on_state_set = function(_, want)
      if setting then return false end
      C.helper({ "ssh", want and "on" or "off" }, nil, function(ok, out)
         if not ok then C.error(C.clean_error(out)) end
         refresh()
      end)
      return true   -- the switch moves when refresh() has read the new state
   end

   local line = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
   line:pack_start(sw, false, false, 0)
   line:pack_start(Gtk.Label { label = "Allow remote access (SSH)", xalign = 0 }, false, false, 0)
   box:pack_start(line, false, false, 0)
   box:pack_start(state, false, false, 0)
   box:pack_start(how, false, false, 0)
   refresh()

   -- 0.9.1: only members of the group "remote" may log in over SSH (default: administrators);
   -- 3 password tries per connection, 30 seconds to log in, never an empty password
   box:pack_start(C.heading("Who may connect"), false, false, 0)
   local who = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 4 }
   local function fill_who()
      C.clear(who)
      local names = {}
      for _, p in ipairs(C.people()) do
         if p.remote then table.insert(names, p.login) end
      end
      who:pack_start(C.text(#names > 0 and table.concat(names, ", ") or "Nobody (switching remote access on is not enough: choose people below).",
         "gobo-value"), false, false, 0)
      who:show_all()
   end
   box:pack_start(who, false, false, 0)
   box:pack_start(C.button("Choose who may connect...", function()
      local d = Gtk.Dialog { title = "Who may connect", transient_for = C.window, modal = true, destroy_with_parent = true }
      d:add_button("Cancel", Gtk.ResponseType.CANCEL)
      d:add_button("Save", Gtk.ResponseType.OK)
      local vbox = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6, margin = 16 }
      vbox:pack_start(C.text("These people may log in from another computer with their password. Simple accounts cannot.", "dim-label"), false, false, 0)
      local checks = {}
      for _, p in ipairs(C.people()) do
         if p.kind ~= "simple" then
            local c = Gtk.CheckButton { label = string.format("%s (%s)", p.login, C.KIND_NAMES[p.kind]), active = p.remote }
            checks[p.login] = c
            vbox:pack_start(c, false, false, 0)
         end
      end
      d:get_content_area():pack_start(vbox, true, true, 0)
      vbox:show_all()
      local r = d:run()
      local chosen = {}
      for login, c in pairs(checks) do if c.active then table.insert(chosen, login) end end
      d:destroy()
      if r ~= Gtk.ResponseType.OK then return end
      C.helper({ "remote-users" }, table.concat(chosen, "\n") .. "\n", function(ok, out)
         if not ok then C.error(C.clean_error(out)) end
         fill_who()
      end)
   end), false, false, 0)
   box:pack_start(C.text("Other computers get 3 password tries per connection and 30 seconds to log in.", "dim-label"), false, false, 0)
   fill_who()
   return outer
end

return P
