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
   return outer
end

return P
