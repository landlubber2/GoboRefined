-- GoboNet's network menu (0.8.1). A patched copy of upstream's widget
-- (gobo.awesome.gobonet, reference copy in look/reference/gobo-widgets/gobonet.lua; same
-- licence as upstream). It runs hidden: spin/network.lua draws the taskbar icon and opens
-- this menu with a fake button press.
--
-- Changes against upstream:
--   * interfaces are looked up again every time they are needed (upstream asked
--     `gobonet interface` once at desktop start and kept the answer in module locals, so a
--     USB Wi-Fi adapter plugged in later was never used: quick-scan and Rescan ran against
--     no interface and the menu only showed the wired entry and "Rescan" - 0.6.2 item 1);
--   * hotplug_check(): called by spin/network.lua every few seconds; when a wireless
--     interface appears it is brought up (gobonet_backend interface-up, setuid) and a full
--     scan is started so the first menu already has networks; an open menu is closed when
--     the interfaces change;
--   * the wired entry says "no cable" (and does nothing) when the carrier is 0 (item 7);
--   * the trailing newline of `gobonet interface` is gone (it ended up in commands);
--   * 0.8.2: no menu opens by itself (see popup_after_scan below).
-- Test hooks: gobonet_menu.sysnet (default /sys/class/net) and gobonet_menu.backend
-- (default gobonet_backend) can point at a fake tree / stub script (vm/serve/net-test.sh).
local gobonet = {}

local gears = require("gears")
local timer = gears.timer
local awful = require("awful")
local wibox = require("wibox")
local beautiful = require("beautiful")
local spawn = require("awful.spawn")
local core_ok, core = pcall(require, "gobo.awesome.gobonet.core")
local popups_ok, popups = pcall(require, "spin.popups")

gobonet.sysnet = "/sys/class/net"
gobonet.backend = "gobonet_backend"

local function pread(cmd)
   local pd = io.popen(cmd, "r")
   if not pd then
      return ""
   end
   local data = pd:read("*a")
   pd:close()
   return data or ""
end

local function readfile(path)
   local f = io.open(path, "r")
   if not f then return nil end
   local ok, s = pcall(f.read, f, "*a")
   f:close()
   if not ok then return nil end
   return s
end

local function q(s)
   return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function list_ifaces()
   local out = {}
   local p = io.popen("ls -1 " .. q(gobonet.sysnet) .. " 2>/dev/null", "r")
   if p then
      for name in p:lines() do table.insert(out, name) end
      p:close()
   end
   table.sort(out)
   return out
end

local function exists(path)
   local f = io.open(path, "r")
   if f then f:close() return true end
   return false
end

-- Same rules as `gobonet interface` / `gobonet wired_interface` (GoboNet 0.12), read from
-- sysfs directly: returns wlan, wired (either may be nil)
function gobonet.detect()
   local wlan, wired
   for _, name in ipairs(list_ifaces()) do
      local base = gobonet.sysnet .. "/" .. name
      local uevent = readfile(base .. "/uevent") or ""
      local is_wlan = uevent:match("DEVTYPE=wlan") ~= nil or exists(base .. "/phy80211")
      if is_wlan then
         wlan = wlan or name
      elseif not uevent:match("DEVTYPE=bridge") and not name:match("^docker") and not name:match("^veth")
         and (readfile(base .. "/type") or ""):match("^1%s*$") then
         wired = wired or name
      end
   end
   return wlan, wired
end

-- "1" cable in, "0" no cable, nil unknown (interface down: the kernel refuses the read)
function gobonet.carrier(ifname)
   local s = readfile(gobonet.sysnet .. "/" .. ifname .. "/carrier")
   return s and s:match("[01]")
end

local function read_wifi_level()
   local fd = io.open("/proc/net/wireless", "r")
   if fd then
      fd:read("*l")
      fd:read("*l")
      local data = fd:read("*l")
      fd:close()
      if data then
         local value = data:match("^%s*[^%s]+:%s+[^%s]+%s*(%d+)")
         if value then
            return tonumber(value)
         end
      end
   end
end

local function quality_icon(quality)
   if quality >= 75 then
      return beautiful.wifi_3_icon
   elseif quality >= 50 then
      return beautiful.wifi_2_icon
   elseif quality >= 25 then
      return beautiful.wifi_1_icon
   else
      return beautiful.wifi_0_icon
   end
end

local run = awful.spawn.with_shell

local function disconnect()
   run("gobonet disconnect")
end

local function forget(essid)
   run("gobonet forget " .. q(essid))
end

local function compact_entries(entries)
   local limit = 20
   if #entries > limit then
      local submenu = {}
      for i = limit + 1, #entries do
         table.insert(submenu, entries[i])
         entries[i] = nil
      end
      compact_entries(submenu)
      table.insert(entries, { "More...", submenu } )
   end
end

function gobonet.new()
   local widget = wibox.widget.imagebox()
   local menu
   local wifi_menu_fn
   local wlan_interface, wired_interface = gobonet.detect()

   local is_scanning = function() return false end
   local is_connecting = function() return false end

   local function animated_operation(args)
      local cmd = args.command
      local on_done = args.on_done
      if not cmd then return end
      local waiting
      local is_waiting = function()
         if not waiting then return false end
         if waiting() ~= true then
            return true
         end
         waiting = nil
         return false
      end
      return function()
         if is_waiting() then
            return is_waiting
         end
         do
            local done = false
            waiting = function()
               return done
            end
            spawn.easy_async_with_shell(cmd, function()
               done = true
            end)
         end
         local frames = args.frames or {
            beautiful.wifi_0_icon,
            beautiful.wifi_1_icon,
            beautiful.wifi_2_icon,
            beautiful.wifi_3_icon,
         }
         local step = 1
         local animation_timer = timer({timeout=0.25})
         local function animate()
            if is_waiting() then
               widget:set_image(frames[step])
               step = step + 1
               if step == #frames + 1 then step = 1 end
            else
               animation_timer:stop()
               if on_done then on_done() end
            end
         end
         animation_timer:connect_signal("timeout", animate)
         animation_timer:start()
         return is_waiting
      end
   end

   local function is_external_scanning()
      local pidfilename = (os.getenv("HOME") or "") .. "/.cache/GoboNet/wifi/.connecting.pid"
      local pidfd = io.open(pidfilename, "r")
      if not pidfd then return false end
      local pid = pidfd:read("*l")
      pidfd:close()
      if not pid or not pid:match("^%d+$") then
         os.remove(pidfilename)
         return false
      end
      local statfilename = "/proc/"..pid.."/stat"
      local statfd = io.open(statfilename, "r")
      if not statfd then
         os.remove(pidfilename)
         return false
      end
      statfd:close()
      is_scanning = animated_operation { command = "while grep -q gobonet "..q(statfilename).."; do sleep 0.5; done; rm -f "..q(pidfilename) } ()
      return true
   end

   -- 0.8.2: when a scan ends, the menu is shown again ONLY for a scan the user asked for:
   --   * "Rescan" clicked (the menu closes on the click): shown again if, at the end of the
   --     scan, no other popup is open, no adapter came or went, and it took under 30 s;
   --   * "Scanning..." (the user opened the menu while nothing was known yet): the open menu is
   --     refreshed, and only if it is still open.
   -- An adapter event or a background scan never opens a menu (0.8.1 did: upstream's
   -- popup_menu_when_done re-opened it from a timer, also long after the user had gone, and
   -- the real PC lost its clicks around such an event).
   local hotplug_gen = 0
   local want_popup   -- { gen = hotplug_gen, deadline = os.time() + 30, need_visible = bool }
   gobonet.auto_popups = 0   -- lab test counter
   local function popup_after_scan()
      local w = want_popup
      want_popup = nil
      if not w or w.gen ~= hotplug_gen or os.time() > w.deadline then return end
      local visible = menu and menu.wibox.visible
      if w.need_visible and not visible then return end
      if not visible and popups_ok and popups.visible_backdrops() > 0 then return end
      if menu then
         menu:hide()
         menu = nil
      end
      gobonet.auto_popups = gobonet.auto_popups + 1
      wifi_menu_fn(true)
   end

   -- Rescan for the current Wi-Fi interface (rebuilt when the interface changes)
   local rescan, rescan_for
   local function do_rescan(need_visible)
      if not wlan_interface then return function() return false end end
      if rescan_for ~= wlan_interface then
         rescan = animated_operation { command = gobonet.backend .. " full-scan " .. q(wlan_interface), on_done = popup_after_scan }
         rescan_for = wlan_interface
      end
      want_popup = { gen = hotplug_gen, deadline = os.time() + 30, need_visible = need_visible }
      return rescan()
   end

   local function connect(essid)
      return animated_operation { command = "gobonet connect " .. q(essid) } ()
   end

   local function autoconnect()
      return animated_operation { command = "gobonet autoconnect" } ()
   end

   local function connect_wired()
      return animated_operation { command = "gobonet connect_wired", frames = { beautiful.wired_up_icon, beautiful.wired_down_icon } } ()
   end

   -- Bring a (new) Wi-Fi interface up and fill the scan cache in the background
   local function wake(ifname)
      spawn.easy_async_with_shell(gobonet.backend .. " interface-up " .. q(ifname) .. " >/dev/null 2>&1; "
         .. gobonet.backend .. " full-scan " .. q(ifname) .. " >/dev/null 2>&1", function() end)
   end

   -- Called every few seconds by spin/network.lua: true when the interfaces changed
   function widget:hotplug_check()
      local wlan, wired = gobonet.detect()
      if wlan == wlan_interface and wired == wired_interface then return false end
      local new_wlan = wlan and wlan ~= wlan_interface
      wlan_interface, wired_interface = wlan, wired
      hotplug_gen = hotplug_gen + 1   -- a scan running now must not bring a menu back
      want_popup = nil
      if menu then
         menu:hide()
         menu = nil
      end
      if new_wlan then wake(wlan) end
      return true
   end
   function widget:interfaces() return wlan_interface, wired_interface end
   if wlan_interface then wake(wlan_interface) end

   local last_update = os.time()
   local function update()
      local prev_update = last_update
      last_update = os.time()
      if is_scanning() or is_connecting() or is_external_scanning() then
         return
      end
      if wired_interface and core_ok then
         local pok, up, running = pcall(core.up_and_running, wired_interface)
         if pok and up and running then
            widget:set_image(beautiful.wired_up_icon)
            return
         end
      end
      local wifi_level = read_wifi_level()
      if not wifi_level then
         if wlan_interface then
            widget:set_image(beautiful.wifi_down_icon)
         else
            widget:set_image(beautiful.wired_down_icon)
         end
         -- A long time elapsed between updates probably means
         -- the computer went asleep. Let's try to autoconnect.
         if last_update - prev_update > 10 and (wlan_interface or wired_interface) then
            is_connecting = autoconnect()
         end
      else
         local quality = (tonumber(wifi_level) / 70) * 100
         widget:set_image(quality_icon(quality))
      end
   end

   -- The menu entries (also used by the lab test without showing a menu)
   function widget:entries(auto_popped)
      local iwconfig = pread("iwconfig 2>/dev/null")
      local my_essid = iwconfig:match('ESSID:"([^\n]*)"%s*\n')
      local scan = ""
      if wlan_interface and not is_scanning() then
         scan = pread(gobonet.backend .. " quick-scan " .. q(wlan_interface) .. " 2>/dev/null")
      end
      local entries = {}
      local curr_entry
      for key, value in scan:gmatch("%s*([^:=]+)[:=]([^\n]*)\n") do
         if key:match("^Cell ") then
            if curr_entry then
               table.insert(entries, curr_entry)
            end
            curr_entry = { [1] = " " .. value:gsub(" ", "") }
         elseif key == "ESSID" and curr_entry then
            local essid = value:match('^"(.*)"$')
            if essid and essid ~= "" then
               local label = " " .. essid
               curr_entry[1] = label
               curr_entry[2] = function() is_connecting = connect(essid) end
            end
         elseif key == "Quality" and curr_entry then
            local cur, max = value:match("^(%d+)/(%d+)")
            if cur then
               local quality = (tonumber(cur) / tonumber(max)) * 100
               curr_entry.quality = quality
               curr_entry[3] = quality_icon(quality)
            end
         end
      end
      if curr_entry then
         table.insert(entries, curr_entry)
      end
      table.sort(entries, function(a,b)
         return (a.quality or 0) > (b.quality or 0)
      end)
      if my_essid and my_essid ~= "" then
         local disconnect_msg = is_connecting() and " Cancel connecting to " or " Disconnect "
         table.insert(entries, 1, { disconnect_msg .. my_essid, function() disconnect() end })
         table.insert(entries, 2, { " Forget " .. my_essid, function() forget(my_essid) end })
      end
      if not wlan_interface then
         table.insert(entries, { " No Wi-Fi adapter found" })
      elseif is_scanning() then
         table.insert(entries, { " Scanning..." })
      elseif #entries == 0 and not auto_popped then
         table.insert(entries, { " Scanning..." })
         is_scanning = do_rescan(true)
      else
         table.insert(entries, { " Rescan", function() is_scanning = do_rescan(false) end } )
      end
      if wired_interface then
         if gobonet.carrier(wired_interface) == "0" then
            table.insert(entries, 1, { " Wired network ("..wired_interface.."): no cable ", nil, beautiful.wired_down_icon })
         else
            table.insert(entries, 1, { " Wired network ("..wired_interface..") ", function() connect_wired() end, beautiful.wired_up_icon })
         end
      end
      return entries
   end

   local coords
   wifi_menu_fn = function(auto_popped)
      if not auto_popped then
         coords = mouse.coords()
      end
      if menu then
         if menu.wibox.visible then
            menu:hide()
            menu = nil
            return
         else
            menu = nil
         end
      end
      local entries = widget:entries(auto_popped)
      local len = 10
      for _, entry in ipairs(entries) do
         len = math.max(len, (#entry[1] + 1) * 10 )
      end
      entries.theme = { height = 24, width = len }
      compact_entries(entries)
      menu = awful.menu.new(entries)
      menu:show({ coords = coords })
   end
   function widget:menu() return menu end

   widget:buttons(gears.table.join(
      awful.button({ }, 1, function() wifi_menu_fn() end ),
      awful.button({ }, 3, function() wifi_menu_fn() end )
   ))

   local wifi_timer = timer({timeout=2})
   wifi_timer:connect_signal("timeout", update)
   update()
   wifi_timer:start()

   return widget
end

return gobonet
