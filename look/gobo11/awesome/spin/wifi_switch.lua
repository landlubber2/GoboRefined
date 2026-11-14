-- Second trigger for Realtek USB Wi-Fi adapters that start as a "driver CD" (0.6).
-- udev's rule (40-gobo-realtek-wifi.rules) should switch them; if that path fails, the
-- desktop does it: at login and whenever the CD (USB ID 0bda:1a2b) is seen, it runs
--   sudo -n /System/Index/bin/gobo-wifi-switch --session
-- (the ISO build adds a NOPASSWD sudo rule for exactly that command). Every attempt is
-- logged by gobo-wifi-switch to /var/log/gobo-wifi-switch.log.
local awful = require("awful")
local gears = require("gears")
local naughty = require("naughty")
local Gio = require("lgi").Gio

local wifi_switch = {}

local VID, PID = "0bda", "1a2b"
local WRAPPER = "/System/Index/bin/gobo-wifi-switch"

local function read(path)
   local f = io.open(path, "r")
   if not f then return nil end
   local s = f:read("*l")
   f:close()
   return s
end

-- is a USB device with that ID present? (a short directory listing, every few seconds)
function wifi_switch.present(vid, pid)
   local dir = Gio.File.new_for_path("/sys/bus/usb/devices")
   local ok, enum = pcall(dir.enumerate_children, dir, "standard::name", Gio.FileQueryInfoFlags.NONE)
   if not ok or not enum then return false end
   local found = false
   while true do
      local info = enum:next_file()
      if not info then break end
      local base = "/sys/bus/usb/devices/" .. info:get_name()
      if read(base .. "/idVendor") == (vid or VID) and read(base .. "/idProduct") == (pid or PID) then
         found = true
         break
      end
   end
   enum:close()
   return found
end

local running = false
local function switch(icon)
   if running then return end
   running = true
   naughty.notify({ title = "Wi-Fi adapter found", text = "Switching it on...", icon = icon, timeout = 6 })
   awful.spawn.easy_async({ "sudo", "-n", WRAPPER, "--session" }, function(_, err, _, code)
      running = false
      if code == 0 then
         naughty.notify({ title = "Wi-Fi adapter ready",
            text = "Click the network icon on the taskbar to pick a network.", icon = icon, timeout = 10 })
      else
         naughty.notify({ title = "Wi-Fi adapter: could not switch it on",
            text = "Details are in /var/log/gobo-wifi-switch.log\n" .. (err or ""):gsub("%s+$", ""),
            icon = icon, timeout = 20 })
      end
   end)
end

-- args.icon: notification icon; args.vid/args.pid: other IDs (lab tests only)
function wifi_switch.start(args)
   args = args or {}
   if args.vid then VID, PID = args.vid, args.pid end
   local f = io.open(WRAPPER, "r")
   if not f then return end   -- image without the wrapper
   f:close()
   local seen = false
   gears.timer({ timeout = 3, autostart = true, call_now = true, callback = function()
      local now = wifi_switch.present()
      -- act once per appearance; udev usually wins, so wait one round before stepping in
      if now and seen == "waited" then
         seen = true
         switch(args.icon)
      elseif now and not seen then
         seen = "waited"
      elseif not now then
         seen = false
      end
   end })
end

return wifi_switch
