-- Hotspot (0.8.2, experimental): share this computer's connection (usually the cable) with
-- phones and other computers over its Wi-Fi adapter. Root work = gobo-settings-helper
-- "hotspot-set" (name + password on stdin; only the derived key is stored, root only) and
-- "hotspot on|off" (wpa_supplicant in access point mode, dnsmasq for addresses, iptables NAT).
-- Starting it stops client Wi-Fi on that adapter (GoboNet); stopping it runs "gobonet
-- autoconnect" as the user, so known Wi-Fi networks come back. Not kept over a restart.
-- The page itself only reads world-readable files: the name, the run state, the lease list.
local P = { id = "hotspot", title = "Hotspot", icon = "network-wireless-hotspot" }

local NAME_FILE = "/Data/Variable/lib/gobo-settings/hotspot.name"
local RUN = "/Data/Variable/run/gobo-hotspot"

function P.build(C)
   local Gtk, GLib = C.Gtk, C.GLib
   local outer, box = C.page("Wi-Fi hotspot",
      "Shares this computer's internet connection (usually the cable) with phones and other computers over its Wi-Fi adapter.")
   box:pack_start(C.text("Experimental: not yet tested on real hardware.", "dim-label"), false, false, 0)

   local function wifi_iface()
      for name in C.pread("ls -1 /sys/class/net"):gmatch("[^\n]+") do
         local base = "/sys/class/net/" .. name
         if C.exists(base .. "/phy80211") or C.exists(base .. "/wireless") then return name end
      end
   end
   local function state()
      local s = C.read(RUN .. "/state")
      if not s then return nil end
      return { iface = s:match("iface=([^\n]*)"), uplink = s:match("uplink=([^\n]*)"), started = s:match("started=([^\n]*)") }
   end
   local function saved_name() return C.trim(C.read(NAME_FILE) or "") end
   local function clients()
      local n = 0
      for _ in (C.read(RUN .. "/leases") or ""):gmatch("[^\n]+") do n = n + 1 end
      return n
   end
   local function client_essid(ifc)
      return ifc and C.trim(C.pread("iwgetid -r " .. C.q(ifc))) or ""
   end

   local sw = Gtk.Switch { valign = Gtk.Align.CENTER }
   local status = C.text("")
   local details = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 6 }
   local setting, busy = false, false

   local refresh, start
   local function edit_settings(then_start)
      local v = C.form("Hotspot name and password", {
         { key = "name", label = "Name (what phones show)", value = saved_name() ~= "" and saved_name() or ("GoboRefined-" .. (C.trim(C.read("/proc/sys/kernel/hostname") or "")):gsub("[^%w-]", "")) },
         { key = "pw", label = "Password", kind = "password" },
         { key = "again", label = "Repeat it", kind = "password" },
      }, "Save", function(v)
         if v.name == "" or #v.name > 32 then return "The name must have 1 to 32 characters." end
         if v.name:match("%c") then return "The name may not contain control characters." end
         if #v.pw < 8 or #v.pw > 63 then return "The password must have 8 to 63 characters." end
         if not v.pw:match("^[ -~]+$") then return "The password may use letters, digits and punctuation only (no accents)." end
         if v.pw ~= v.again then return "The two passwords are not the same." end
      end)
      if not v then refresh() return end
      busy = true
      status.label = "Saving..."
      C.helper({ "hotspot-set" }, v.name .. "\n" .. v.pw .. "\n", function(ok, out)
         busy = false
         if not ok then C.error(C.clean_error(out)) refresh() return end
         if then_start then
            start(refresh)
         else
            refresh()
         end
      end)
   end

   start = function(after)
      local ifc = wifi_iface()
      local essid = client_essid(ifc)
      local q = "Turn the hotspot on?\n\nThe Wi-Fi adapter can either join a network or be a hotspot, not both."
      if essid ~= "" then
         q = q .. " This computer will leave the Wi-Fi network \"" .. essid .. "\" now; turning the hotspot off joins it again."
      end
      if not C.confirm(q, "Turn on") then after() return end
      busy = true
      status.label = "Starting the hotspot..."
      C.helper({ "hotspot", "on" }, nil, function(ok, out)
         busy = false
         if not ok then
            C.error("The hotspot did not start.\n\n" .. C.clean_error(out))
            C.spawn({ "gobonet", "autoconnect" })
         end
         after()
      end)
   end

   local function stop()
      busy = true
      status.label = "Stopping the hotspot..."
      C.helper({ "hotspot", "off" }, nil, function(ok, out)
         busy = false
         if not ok then C.error(C.clean_error(out)) end
         -- client Wi-Fi back (known networks of this user, as at login)
         C.spawn({ "gobonet", "autoconnect" })
         refresh()
      end)
   end

   sw.on_state_set = function(_, want)
      if setting or busy then return true end
      if want then
         if saved_name() == "" then edit_settings(true) else start(refresh) end
      else
         stop()
      end
      return true   -- the switch follows refresh()
   end

   local edit_button = C.button("Name and password...", function() edit_settings(false) end)

   refresh = function()
      local ifc = wifi_iface()
      local st = state()
      setting = true
      sw.active = st ~= nil
      sw.state = st ~= nil
      setting = false
      sw.sensitive = ifc ~= nil or st ~= nil
      edit_button.sensitive = true
      C.clear(details)
      if not ifc and not st then
         status.label = "Needs a Wi-Fi adapter. None was found; plug one in and this page notices it."
      elseif st then
         status.label = "On: devices can join \"" .. saved_name() .. "\" with the password you set."
         details:pack_start(C.text("Wi-Fi adapter: " .. (st.iface or "?") .. ", since " .. (st.started or "?")), false, false, 0)
         if st.uplink and st.uplink ~= "" then
            details:pack_start(C.text("Internet shared from: " .. st.uplink), false, false, 0)
         else
            details:pack_start(C.text("No internet connection to share right now (plug in the cable); devices can still reach this computer."), false, false, 0)
         end
         local n = clients()
         details:pack_start(C.text(n == 1 and "1 device has joined." or (n .. " devices have joined."), "gobo-value"), false, false, 0)
      else
         local name = saved_name()
         status.label = "Off." .. (name ~= "" and ("  Name: \"" .. name .. "\"") or "  Set a name and password first (the switch asks for them).")
         details:pack_start(C.text("Wi-Fi adapter: " .. ifc .. ". Whether it can be a hotspot is checked when you turn it on.", "dim-label"), false, false, 0)
      end
      details:pack_start(C.text("Only administrators can change the hotspot. It stays off after a restart.", "dim-label"), false, false, 0)
      details:show_all()
   end

   local line = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 12 }
   line:pack_start(sw, false, false, 0)
   line:pack_start(Gtk.Label { label = "Wi-Fi hotspot", xalign = 0 }, false, false, 0)
   box:pack_start(line, false, false, 0)
   box:pack_start(status, false, false, 0)
   box:pack_start(details, false, false, 0)
   box:pack_start(C.row(edit_button, C.button("Refresh", function() refresh() end)), false, false, 0)
   refresh()

   -- notice an adapter being plugged in or out, and devices joining
   GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 4, function()
      if not outer:get_mapped() or busy then return true end
      refresh()
      return true
   end)
   return outer
end

return P
