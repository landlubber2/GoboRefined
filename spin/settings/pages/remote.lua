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
   return outer
end

return P
