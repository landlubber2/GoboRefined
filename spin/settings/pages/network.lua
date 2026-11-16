-- Network: state and addresses; the network menu of the taskbar does the choosing (Wi-Fi list,
-- wired, rescan). Wi-Fi hotspot: 0.8.2 part 2 (pages/hotspot.lua placeholder).
local P = { id = "network", title = "Network", icon = "network-wired" }

function P.build(C)
   local outer, box = C.page("Network")
   local info = C.Gtk.Box { orientation = C.Gtk.Orientation.VERTICAL, spacing = 6 }
   local function refresh()
      C.clear(info)
      local any = false
      for name in C.pread("ls -1 /sys/class/net"):gmatch("[^\n]+") do
         if name ~= "lo" then
            any = true
            local base = "/sys/class/net/" .. name
            local wifi = C.exists(base .. "/wireless") or C.exists(base .. "/phy80211")
            local oper = C.trim(C.read(base .. "/operstate") or "?")
            local addr = {}
            for a in C.pread("ip -o addr show dev " .. C.q(name)):gmatch("inet6? ([%x:.]+/%d+)") do table.insert(addr, a) end
            local essid = wifi and C.trim(C.pread("iwgetid -r " .. C.q(name))) or ""
            info:pack_start(C.text(string.format("%s %s: %s%s", wifi and "Wi-Fi" or "Wired", name,
               oper == "up" and "connected" or oper, essid ~= "" and (" to " .. essid) or ""), "gobo-value"), false, false, 0)
            info:pack_start(C.text(#addr > 0 and table.concat(addr, "   ") or "no address", "dim-label"), false, false, 0)
         end
      end
      if not any then info:pack_start(C.text("No network adapter found."), false, false, 0) end
      local route = C.pread("ip route show default"):match("via ([%d.]+)")
      if route then info:pack_start(C.text("Router (default gateway): " .. route), false, false, 0) end
      info:show_all()
   end
   box:pack_start(C.heading("Adapters"), false, false, 0)
   box:pack_start(info, false, false, 0)
   box:pack_start(C.row(
      C.button("Open the network menu", function() C.desktop("if spin_open_network_menu then spin_open_network_menu() end") end, "suggested-action"),
      C.button("Refresh", refresh)), false, false, 0)
   box:pack_start(C.text("The network menu (the network icon on the taskbar) lists Wi-Fi networks, connects and disconnects.", "dim-label"), false, false, 0)
   refresh()

   -- 0.9.1: firewall (gobo-firewall): nothing comes in unless it answers this computer; Remote
   -- access and the hotspot open what they need while they are on. Administrators switch it.
   local OFF_FLAG = "/Data/Variable/lib/gobo-settings/firewall-off"
   local ACTIVE = "/Data/Variable/run/gobo-firewall.active"
   box:pack_start(C.heading("Firewall"), false, false, 0)
   local fw_state = C.text("")
   local sw = C.Gtk.Switch { valign = C.Gtk.Align.CENTER }
   local setting = false
   local function fw_refresh()
      setting = true
      sw.active = not C.exists(OFF_FLAG)
      sw.state = sw.active
      setting = false
      local on, active = not C.exists(OFF_FLAG), C.exists(ACTIVE)
      fw_state.label = on and (active and "On: other computers cannot connect to this one (except Remote access and the hotspot while they are on)."
                                      or "On, but not running (see /Data/Variable/log/gobo-firewall.log).")
                          or "Off: other computers on the network can reach every service of this computer."
   end
   sw.on_state_set = function(_, want)
      if setting then return false end
      C.helper({ "firewall", want and "on" or "off" }, nil, function(ok, out)
         if not ok then C.error(C.clean_error(out)) end
         fw_refresh()
      end)
      return true
   end
   sw.sensitive = C.is_admin()
   local line = C.Gtk.Box { orientation = C.Gtk.Orientation.HORIZONTAL, spacing = 12 }
   line:pack_start(sw, false, false, 0)
   line:pack_start(C.Gtk.Label { label = "Firewall", xalign = 0 }, false, false, 0)
   box:pack_start(line, false, false, 0)
   box:pack_start(fw_state, false, false, 0)
   if not C.is_admin() then
      box:pack_start(C.text("Only an administrator can switch the firewall.", "dim-label"), false, false, 0)
   end
   fw_refresh()
   return outer
end

return P
