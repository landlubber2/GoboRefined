-- Taskbar Bluetooth icon and menu (0.8.4). Replaces upstream's gobo.awesome.bluetooth widget,
-- whose device entries ran `bluetoothctl pair` with no pairing agent (pairing failed with
-- "incorrect PIN or passkey") and which listed every nearby address. One Bluetooth experience:
--   * the icon shows while the computer has a Bluetooth adapter (also one plugged in later);
--   * the menu: Bluetooth on/off, the paired devices (click: connect / disconnect),
--     "Bluetooth settings..." (Settings > Bluetooth: search, pair, forget).
-- Pairing questions are answered in the dialogs of the session's agent (gobo-bt-agent).
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local naughty = require("naughty")

local bluetooth = {}

local MAC = "^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$"

local function adapter_present()
   local p = io.popen("ls -1 /sys/class/bluetooth 2>/dev/null")
   if not p then return false end
   local s = p:read("*a") or ""
   p:close()
   return s:match("hci%d") ~= nil
end

-- one shell run: controller state, then the paired devices with their info
local QUERY = [[t() { timeout 5 bluetoothctl "$@" 2>/dev/null; }
pgrep -x bluetoothd > /dev/null || { echo NODAEMON; exit 0; }
t show; echo "==DEVICES"
for m in $(t paired-devices | grep -o 'Device [0-9A-F:]\{17\}' | cut -d' ' -f2 | sort -u); do echo "==DEV $m"; t info "$m"; done]]

local function parse(out)
   local st = { daemon = not out:match("NODAEMON"), devices = {} }
   st.controller = out:match("Controller %x%x:") ~= nil
   st.powered = out:match("Powered: yes") ~= nil
   for piece in (out:match("==DEVICES(.*)$") or ""):gmatch("==DEV ([^=]*)") do
      local mac = piece:match("^(%S+)")
      local info = "\n" .. piece
      if mac and mac:match(MAC) then
         local name = info:match("\n%s*Alias: ([^\n]+)") or info:match("\n%s*Name: ([^\n]+)") or mac
         table.insert(st.devices, { mac = mac, name = name:gsub("%s+$", ""),
            connected = info:match("Connected: yes") ~= nil })
      end
   end
   table.sort(st.devices, function(a, b) return a.name:lower() < b.name:lower() end)
   return st
end

-- args: icon_on, icon_off (paths)
function bluetooth.new(args)
   args = args or {}
   local widget = wibox.widget.imagebox(args.icon_off or args.icon_on)
   widget.visible = false
   local state = { daemon = false, devices = {} }
   local menu
   local busy = false

   local function show_icon()
      widget.image = (state.powered and args.icon_on) or args.icon_off or args.icon_on
   end

   local function refresh(after)
      if not adapter_present() then
         widget.visible = false
         state = { daemon = false, devices = {} }
         if after then after() end
         return
      end
      widget.visible = true
      if busy then
         if after then after() end   -- a query is running: use the state we have
         return
      end
      busy = true
      awful.spawn.easy_async({ "sh", "-c", QUERY }, function(out)
         busy = false
         state = parse(out or "")
         show_icon()
         if after then after() end
      end)
   end

   local function run(argv, done_text, fail_text)
      awful.spawn.easy_async(argv, function(out, _, _, code)
         out = out or ""
         if code ~= 0 or out:match("Failed") or out:match("not available") then
            naughty.notify({ title = "Bluetooth", text = fail_text, timeout = 8 })
         elseif done_text then
            naughty.notify({ title = "Bluetooth", text = done_text, timeout = 4 })
         end
         refresh()
      end)
   end

   local function settings() awful.spawn({ "gobo-settings", "bluetooth" }) end

   local function show_menu()
      if menu and menu.wibox.visible then menu:hide() menu = nil return end
      local items = {}
      if not state.daemon then
         table.insert(items, { "Bluetooth service is not running", settings })
      elseif not state.controller then
         table.insert(items, { "Bluetooth adapter not ready", settings })
      elseif state.powered then
         table.insert(items, { "Bluetooth is on: switch off", function()
            run({ "timeout", "10", "bluetoothctl", "power", "off" }, nil, "Could not switch Bluetooth off.")
         end })
         for _, d in ipairs(state.devices) do
            if d.connected then
               table.insert(items, { "Disconnect " .. d.name, function()
                  run({ "timeout", "20", "bluetoothctl", "disconnect", d.mac }, d.name .. " disconnected.",
                      "Could not disconnect " .. d.name .. ".")
               end })
            else
               table.insert(items, { "Connect " .. d.name, function()
                  naughty.notify({ title = "Bluetooth", text = "Connecting " .. d.name .. "...", timeout = 3 })
                  run({ "timeout", "25", "bluetoothctl", "connect", d.mac }, d.name .. " connected.",
                      "Could not connect " .. d.name .. ". Is it switched on and nearby?")
               end })
            end
         end
      else
         table.insert(items, { "Bluetooth is off: switch on", function()
            run({ "timeout", "10", "bluetoothctl", "power", "on" }, nil,
                "Could not switch Bluetooth on (it may be blocked: see Bluetooth settings).")
         end })
      end
      table.insert(items, { "Bluetooth settings...", settings })
      menu = awful.menu({ items = items, theme = { width = 280 } })
      menu:show()
   end

   widget:buttons(gears.table.join(
      awful.button({}, 1, function() refresh(show_menu) end),
      awful.button({}, 3, function() refresh(show_menu) end)))
   awful.tooltip({ objects = { widget }, timer_function = function()
      if not state.daemon then return "Bluetooth" end
      local n = 0
      for _, d in ipairs(state.devices) do if d.connected then n = n + 1 end end
      return "Bluetooth: " .. (state.powered and "on" or "off") .. (n > 0 and (", " .. n .. " connected") or "")
   end })

   gears.timer({ timeout = 5, autostart = true, call_now = true, callback = function() refresh() end })
   return widget
end

return bluetooth
